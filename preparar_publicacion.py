#!/usr/bin/env python3
"""Construye la publicación a partir de los CSV del motor PFC Glicko-2 en R."""
import argparse
import csv
import json
import math
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


def leer_csv(archivo):
    with archivo.open('r', encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def numero(valor):
    if valor is None or str(valor).strip() in ('', 'NA', 'NaN'):
        return None
    resultado = float(valor)
    if not math.isfinite(resultado):
        raise ValueError('Se encontró un número no finito en la salida del motor.')
    return resultado


def entero(valor):
    n = numero(valor)
    if n is None or not n.is_integer() or n < 0:
        raise ValueError('Se encontró un contador no válido en la salida del motor.')
    return int(n)


def booleano(valor):
    texto = str(valor).strip().upper()
    if texto in ('TRUE', 'T', '1'):
        return True
    if texto in ('FALSE', 'F', '0'):
        return False
    raise ValueError('El campo calificable no contiene un valor válido.')


def es_desert(valor):
    return str(valor or '').strip().upper() == 'DESERT'


def construir(datos: Path, plantilla: Path, destino: Path):
    ranking = leer_csv(datos / 'ranking_conservador_beta31.csv')
    historial = leer_csv(datos / 'historial_completo.csv')
    combates = leer_csv(datos / 'combates_auditados.csv')
    pendientes = datos / 'combates_incompletos.csv'
    incompletos = leer_csv(pendientes) if pendientes.exists() else []
    if incompletos:
        raise ValueError(f'Hay {len(incompletos)} identificadores de combate incompletos o inconsistentes; se conserva la publicación anterior.')
    if not ranking or not combates:
        raise ValueError('La salida no contiene atletas o combates; se conserva la publicación anterior.')
    if any(es_desert(r.get('atleta')) for r in ranking):
        raise ValueError('El marcador DESERT aparece como atleta; se detiene la publicación.')

    excepciones = [c for c in combates if not booleano(c['calificable'])]
    sin_resolver = [c for c in excepciones if not (es_desert(c.get('ganador')) or es_desert(c.get('perdedor')))]
    if sin_resolver:
        raise ValueError(f'Hay {len(sin_resolver)} combates no calificables por datos distintos a DESERT; se conserva la publicación anterior.')

    por_atleta = defaultdict(list)
    historiales_invalidos = 0
    for h in historial:
        if es_desert(h.get('atleta')):
            historiales_invalidos += 1
            continue
        registro = {k: h.get(k, '') for k in ('fecha', 'torneo', 'circuito', 'categoria', 'ronda', 'id_combate', 'oponente', 'resultado')}
        for k in ('numero_combate', 'rating_previo', 'rating_actual', 'rd_previo', 'rd_actual', 'probabilidad'):
            registro[k] = numero(h.get(k))
        registro['calificable'] = booleano(h['calificable'])
        por_atleta[h['atleta']].append(registro)
    if historiales_invalidos:
        raise ValueError('El marcador DESERT tiene una ficha en el historial del motor.')

    atletas = []
    vistos = set()
    for r in ranking:
        atleta = (r.get('atleta') or '').strip()
        if not atleta or atleta in vistos:
            raise ValueError('El ranking contiene nombres vacíos o duplicados.')
        vistos.add(atleta)
        ficha = {k: r.get(k, '') for k in ('rama', 'pais', 'estatus')}
        ficha['atleta'] = atleta
        for k in ('rating', 'rd', 'conservador'):
            ficha[k] = numero(r.get(k))
        for k in ('combates', 'combates_calificables', 'victorias', 'derrotas', 'torneos', 'torneos_con_victoria'):
            ficha[k] = entero(r.get(k))
        ficha['historial'] = por_atleta.get(atleta, [])
        if len(ficha['historial']) != ficha['combates']:
            raise ValueError('Un conteo de combates no coincide con el historial.')
        atletas.append(ficha)
    if set(por_atleta) - vistos:
        raise ValueError('Hay historiales sin un atleta en el ranking.')
    n_calif = sum(booleano(c['calificable']) for c in combates)
    if sum(a['combates_calificables'] for a in atletas) != n_calif * 2:
        raise ValueError('Los combates calificables no cuadran con los historiales de ambos atletas.')

    fechas = [c['fecha'] for c in combates if c.get('fecha')]
    actualizado = datetime.now(ZoneInfo('America/Mexico_City')).strftime('%d/%m/%Y %H:%M')
    meta = {'fecha_actualizacion_cdmx': actualizado, 'fecha_ultimo_evento': max(fechas) if fechas else None,
            'eventos_con_combates': len({c['evento'] for c in combates}), 'combates_reconstruidos': len(combates),
            'combates_calificables': n_calif, 'registros_desert': len(excepciones), 'atletas': len(atletas),
            'metodologia': 'Glicko-2 experimental, actualización por evento y rama'}
    html = plantilla.read_text(encoding='utf-8')
    if any(html.count(x) != 1 for x in ('__DATA__', '__COBERTURA__', '__INCIDENCIAS__')):
        raise ValueError('La plantilla HTML no contiene los marcadores esperados.')
    datos_seguros = json.dumps(atletas, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    cobertura = f"{meta['eventos_con_combates']} eventos · {len(combates):,} combates reconstruidos · {len(atletas):,} atletas"
    html = html.replace('__DATA__', datos_seguros).replace('__COBERTURA__', cobertura).replace('__INCIDENCIAS__', str(len(excepciones)))
    html = html.replace('Glicko-2 · Datos 2025–2026', 'Glicko-2 · Datos recopilados por Point Fight Club')
    html = html.replace('Fuente: base PFC-Elo 4.6; cálculos reproducidos con Glicko-2, períodos por evento.', 'Fuente: base de resultados de Point Fight Club; cálculos Glicko-2 por evento.')
    html = html.replace('</header>', f'<div class="note">Actualizado: {actualizado} · hora de Ciudad de México</div></header>', 1)
    previo = "Math.round(list.reduce((s,x)=>s+x.combates,0)/2).toLocaleString('es-MX')"
    actualizado_js = "new Set(list.flatMap(x=>x.historial.map(h=>JSON.stringify([h.torneo,h.id_combate])))).size.toLocaleString('es-MX')"
    if html.count(previo) != 1:
        raise ValueError('No se encontró el contador de combates de la plantilla.')
    html = html.replace(previo, actualizado_js)
    destino.mkdir(parents=True, exist_ok=True)
    (destino / 'index.html').write_text(html, encoding='utf-8')
    (destino / 'ranking.json').write_text(json.dumps(atletas, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    (destino / 'actualizacion.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding='utf-8')
    return meta


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description='Preparar el ranking público PFC.')
    ap.add_argument('--datos', required=True, type=Path)
    ap.add_argument('--plantilla', required=True, type=Path)
    ap.add_argument('--destino', required=True, type=Path)
    args = ap.parse_args()
    try:
        print(json.dumps(construir(args.datos, args.plantilla, args.destino), ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError) as e:
        raise SystemExit(f'No se publicó el ranking: {e}')
