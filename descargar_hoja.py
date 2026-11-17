#!/usr/bin/env python3
"""Descarga una copia XLSX de una hoja accesible mediante enlace de Google."""
import os
import re
import sys
import urllib.error
import urllib.request
import zipfile
from pathlib import Path


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Uso: python descargar_hoja.py archivo_salida.xlsx')
    ident = os.environ.get('GOOGLE_SHEET_ID', '').strip()
    if not re.fullmatch(r'[A-Za-z0-9_-]{20,120}', ident):
        raise SystemExit('Falta GOOGLE_SHEET_ID o su formato no es válido.')
    url = f'https://docs.google.com/spreadsheets/d/{ident}/export?format=xlsx'
    req = urllib.request.Request(url, headers={'User-Agent': 'PFC-Ranking/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=90) as respuesta:
            contenido = respuesta.read(25 * 1024 * 1024 + 1)
    except (urllib.error.URLError, TimeoutError) as e:
        raise SystemExit(f'No se pudo descargar la hoja. Revisa sus permisos y la conexión ({type(e).__name__}).')
    if len(contenido) > 25 * 1024 * 1024:
        raise SystemExit('La descarga supera el límite de seguridad de 25 MB.')
    destino = Path(sys.argv[1])
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_bytes(contenido)
    if not zipfile.is_zipfile(destino):
        destino.unlink(missing_ok=True)
        raise SystemExit('La respuesta de Google no es un XLSX. Comprueba que la hoja sea accesible por enlace.')
    with zipfile.ZipFile(destino) as libro:
        if 'xl/workbook.xml' not in libro.namelist():
            destino.unlink(missing_ok=True)
            raise SystemExit('La descarga no contiene un libro de Excel válido.')
    print('Copia temporal de la hoja descargada y reconocida como XLSX.')


if __name__ == '__main__':
    main()
