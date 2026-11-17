# PFC Rating Beta 3.1 — Glicko-2 en R
# Requiere: install.packages('readxl')
# Uso: Rscript pfc_glicko2.R "resultados.xlsx" "salida_R"
# Replicación metodológica del motor Python PFC Rating Engine 1.0.

suppressPackageStartupMessages(library(readxl))
args <- commandArgs(trailingOnly=TRUE)
archivo <- if (length(args)>=1) args[1] else 'resultados.xlsx'
destino <- if (length(args)>=2) args[2] else 'salida_R'
if (!file.exists(archivo)) stop('No existe el Excel: ', archivo)
dir.create(destino, showWarnings=FALSE, recursive=TRUE)

ESCALA <- 173.7178
TAU <- 0.5
INICIAL <- c(mu=0, phi=350/ESCALA, sigma=0.06)

# Fórmulas originales Glicko-2 (escala interna).
g <- function(phi) 1/sqrt(1+3*phi^2/pi^2)
expectativa <- function(mu, mu_rival, phi_rival) {
  plogis(g(phi_rival)*(mu-mu_rival))
}
actualizar <- function(estado, rivales) {
  mu <- unname(estado['mu']); phi <- unname(estado['phi']); sigma <- unname(estado['sigma'])
  if (nrow(rivales)==0) return(c(mu=mu,phi=sqrt(phi^2+sigma^2),sigma=sigma))
  gs <- g(rivales$phi)
  es <- plogis(gs*(mu-rivales$mu))
  inv_v <- sum(gs^2*es*(1-es))
  if (inv_v<=0) return(estado)
  v <- 1/inv_v
  delta <- v*sum(gs*(rivales$score-es))
  a <- log(sigma^2)
  f <- function(x) {
    ex <- exp(x)
    ex*(delta^2-phi^2-v-ex)/(2*(phi^2+v+ex)^2)-(x-a)/TAU^2
  }
  A <- a
  if (delta^2>phi^2+v) {
    B <- log(delta^2-phi^2-v)
  } else {
    k <- 1L; B <- a-k*TAU
    while (f(B)<0 && k<100L) {k<-k+1L; B<-a-k*TAU}
  }
  fA <- f(A); fB <- f(B)
  for (iter in seq_len(100)) {
    if (abs(B-A)<1e-7) break
    C <- A+(A-B)*fA/(fB-fA)
    fC <- f(C)
    if (fC*fB<=0) {A<-B;fA<-fB} else fA<-fA/2
    B<-C;fB<-fC
  }
  sigma_n <- exp(A/2)
  phi_star <- sqrt(phi^2+sigma_n^2)
  phi_n <- 1/sqrt(1/phi_star^2+1/v)
  mu_n <- mu+phi_n^2*sum(gs*(rivales$score-es))
  c(mu=mu_n,phi=phi_n,sigma=sigma_n)
}

# Las hojas se identifican por nombre, como en la fuente original.
res <- as.data.frame(read_excel(archivo,sheet='results',col_types='text'))
ev <- as.data.frame(read_excel(archivo,sheet='event',col_types='text'))
at <- as.data.frame(read_excel(archivo,sheet='atletas',col_types='text'))
if (ncol(res)<8 || ncol(ev)<6 || ncol(at)<5) stop('Estructura de hojas incompatible con la base PFC original')
# Mapeo por posición, idéntico al utilizado por el motor Python.
# results: categoria, round, atleta, points, result, event, NUMBER_MATCH, ID_MATCH
# event: nombre en columna 1, circuito en 2, fecha Excel en 6
# atletas: nombre en columna 1, país en 2, género en 5
names(res)[1:8] <- c('categoria','ronda','atleta','puntos','resultado','evento','numero','id_combate')
names(ev)[c(1,2,6)] <- c('evento','circuito','fecha_excel')
names(at)[c(1,2,5)] <- c('atleta','pais','genero')
res[] <- lapply(res, function(x) if (is.character(x)) trimws(x) else x)
ev[] <- lapply(ev, function(x) if (is.character(x)) trimws(x) else x)
at[] <- lapply(at, function(x) if (is.character(x)) trimws(x) else x)

# Reconstrucción de combates: dos filas, una WIN y una LOSE.
llaves <- paste(res$evento,res$id_combate,sep='|||')
grupos <- split(seq_len(nrow(res)),llaves)
peleas <- list(); incidencias <- list()
for (ids in grupos) {
  r <- res[ids,,drop=FALSE]
  if (nrow(r)!=2 || !identical(sort(r$resultado),c('LOSE','WIN')) ||
      identical(r$atleta[1],r$atleta[2])) {
    incidencias[[length(incidencias)+1L]] <- data.frame(evento=r$evento[1],id_combate=r$id_combate[1],motivo='Combate incompleto o inconsistente')
    next
  }
  w <- r[r$resultado=='WIN',,drop=FALSE][1,]
  l <- r[r$resultado=='LOSE',,drop=FALSE][1,]
  e <- ev[ev$evento==w$evento,,drop=FALSE]
  if (!nrow(e)) {
    incidencias[[length(incidencias)+1L]] <- data.frame(evento=w$evento,id_combate=w$id_combate,motivo='Evento sin ficha')
    next
  }
  # La fecha en la fuente es el serial de Excel.
  fecha <- as.Date(as.numeric(e$fecha_excel[1]),origin='1899-12-30')
  if (is.na(fecha)) stop('Fecha no válida para evento: ',w$evento)
  peleas[[length(peleas)+1L]] <- data.frame(
    fecha=as.character(fecha),evento=w$evento,circuito=e$circuito[1],
    categoria=w$categoria,ronda=w$ronda,numero=as.numeric(w$numero),
    id_combate=w$id_combate,ganador=w$atleta,perdedor=l$atleta,
    stringsAsFactors=FALSE)
}
if (!length(peleas)) stop('No se reconstruyeron combates válidos')
m <- do.call(rbind,peleas)
orden_ronda <- c('Round of 64'=0,'Round of 32'=1,'Round of 16'=2,
                 'Quarter Final'=3,'Semi Final'=4,'Final'=5)
m$orden_ronda <- unname(orden_ronda[m$ronda]);m$orden_ronda[is.na(m$orden_ronda)]<-2
m <- m[order(m$fecha,m$evento,m$orden_ronda,m$numero,m$id_combate),]
rownames(m)<-NULL

# Género validado contra las fichas; categoría solo se usa para detectar conflicto.
mapa_genero <- setNames(at$genero,at$atleta)
mapa_pais <- setNames(at$pais,at$atleta)
es_marcador <- function(nombre) !is.na(nombre) & toupper(trimws(nombre)) == 'DESERT'
rama <- function(n) {
  if (length(n)==0 || is.na(n) || es_marcador(n)) return(NA_character_)
  x<-unname(mapa_genero[n]); if (length(x)==0 || is.na(x)) return(NA_character_)
  if (x=='FEMENIL') return('Femenil')
  if (x=='MASCULINO') return('Varonil')
  NA_character_
}
rama_cat <- function(s) {
  if (grepl('\\b(WOMEN|FEMALE|GIRLS|FEMENIL)\\b|\\bS F\\b',toupper(s),perl=TRUE)) return('Femenil')
  if (grepl('\\b(MEN|MALE|BOYS|MASCULINO)\\b|\\bS M\\b',toupper(s),perl=TRUE)) return('Varonil')
  NA_character_
}
m$rama <- NA_character_;m$calificable <- FALSE;m$motivo <- ''
for (i in seq_len(nrow(m))) {
  a<-rama(m$ganador[i]);b<-rama(m$perdedor[i]);c<-rama_cat(m$categoria[i])
  m$rama[i]<-if (!is.na(c)) c else if (!is.na(a)) a else if (!is.na(b)) b else 'Sin determinar'
  m$calificable[i]<-!is.na(a) && !is.na(b) && a==b && (is.na(c) || c==a)
  if (!m$calificable[i]) m$motivo[i]<-'Rama ausente, incompatible o diferente entre rivales'
}

# Estados individuales y periodos de evaluación por evento y rama.
estados <- new.env(parent=emptyenv());historias<-list()
obtener <- function(nombre) if (exists(nombre,envir=estados,inherits=FALSE)) get(nombre,envir=estados) else INICIAL
historial <- list()
periodos <- unique(m[m$calificable,c('rama','fecha','evento')])
periodos <- periodos[order(periodos$rama,periodos$fecha,periodos$evento),]
for (i in seq_len(nrow(periodos))) {
  p<-periodos[i,]
  juegos<-m[m$calificable & m$rama==p$rama & m$fecha==p$fecha & m$evento==p$evento,,drop=FALSE]
  involucrados<-unique(c(juegos$ganador,juegos$perdedor))
  previo<-setNames(lapply(involucrados,obtener),involucrados)
  rivales<-setNames(lapply(involucrados,function(x) data.frame(mu=numeric(),phi=numeric(),score=numeric())),involucrados)
  probabilidades<-numeric(nrow(juegos))
  for (j in seq_len(nrow(juegos))) {
    a<-juegos$ganador[j];b<-juegos$perdedor[j]
    sa<-previo[[a]];sb<-previo[[b]]
    probabilidades[j]<-expectativa(sa['mu'],sb['mu'],sb['phi'])
    rivales[[a]]<-rbind(rivales[[a]],data.frame(mu=unname(sb['mu']),phi=unname(sb['phi']),score=1))
    rivales[[b]]<-rbind(rivales[[b]],data.frame(mu=unname(sa['mu']),phi=unname(sa['phi']),score=0))
  }
  posterior<-lapply(involucrados,function(a) actualizar(previo[[a]],rivales[[a]]));names(posterior)<-involucrados
  for (a in involucrados) assign(a,posterior[[a]],envir=estados)
  for (j in seq_len(nrow(juegos))) {
    pelea<-juegos[j,]
    for (vencedor in c(TRUE,FALSE)) {
      a<-if (vencedor) pelea$ganador else pelea$perdedor
      b<-if (vencedor) pelea$perdedor else pelea$ganador
      s0<-previo[[a]];s1<-posterior[[a]]
      historial[[length(historial)+1L]]<-data.frame(
        atleta=a,rama=pelea$rama,fecha=pelea$fecha,torneo=pelea$evento,
        circuito=ifelse(pelea$circuito=='NASKA','ISKA–NASKA',pelea$circuito),
        categoria=pelea$categoria,ronda=pelea$ronda,numero_combate=pelea$numero,
        id_combate=pelea$id_combate,oponente=b,
        resultado=ifelse(vencedor,'Victoria','Derrota'),
        rating_previo=round(1500+ESCALA*s0['mu'],1),
        rating_actual=round(1500+ESCALA*s1['mu'],1),
        rd_previo=round(ESCALA*s0['phi'],1),
        rd_actual=round(ESCALA*s1['phi'],1),
        probabilidad=round(100*if(vencedor) probabilidades[j] else 1-probabilidades[j],1),
        calificable=TRUE,stringsAsFactors=FALSE)
    }
  }
}
# Combates no calificables siguen visibles en el historial, sin rating inventado.
for (i in which(!m$calificable)) {
  pelea<-m[i,]
  for (vencedor in c(TRUE,FALSE)) {
    a<-if(vencedor) pelea$ganador else pelea$perdedor
    b<-if(vencedor) pelea$perdedor else pelea$ganador
    historial[[length(historial)+1L]]<-data.frame(
      atleta=a,rama=pelea$rama,fecha=pelea$fecha,torneo=pelea$evento,
      circuito=ifelse(pelea$circuito=='NASKA','ISKA–NASKA',pelea$circuito),
      categoria=pelea$categoria,ronda=pelea$ronda,numero_combate=pelea$numero,
      id_combate=pelea$id_combate,oponente=b,resultado=ifelse(vencedor,'Victoria','Derrota'),
      rating_previo=NA_real_,rating_actual=NA_real_,rd_previo=NA_real_,rd_actual=NA_real_,
      probabilidad=NA_real_,calificable=FALSE,stringsAsFactors=FALSE)
  }
}
h <- do.call(rbind,historial)
# Conservar la incidencia y la fila del rival real, sin crear un historial para el marcador.
h <- h[!es_marcador(h$atleta),,drop=FALSE]
h <- h[order(h$atleta,h$fecha,h$torneo,match(h$ronda,names(orden_ronda)),h$numero_combate,h$id_combate),]
rownames(h)<-NULL

# Ranking: todas las personas de la ficha original y los combates, incluso sin rating.
nombres <- sort(unique(c(at$atleta,m$ganador,m$perdedor)))
nombres <- nombres[!es_marcador(nombres)]
ranking <- lapply(nombres,function(a) {
  sub<-h[h$atleta==a,,drop=FALSE]
  st<-if(exists(a,envir=estados,inherits=FALSE)) get(a,envir=estados) else NULL
  ga<-rama(a)
  if(is.na(ga)) {
    cats<-m$categoria[m$ganador==a | m$perdedor==a]
    gs<-vapply(cats,rama_cat,character(1));gs<-gs[!is.na(gs)]
    ga<-if(length(gs)) names(sort(table(gs),decreasing=TRUE))[1] else 'Sin determinar'
  }
  rating<-if(is.null(st)) NA_real_ else round(1500+ESCALA*st['mu'],1)
  rd<-if(is.null(st)) NA_real_ else round(ESCALA*st['phi'],1)
  n_calif<-sum(sub$calificable)
  torneos<-length(unique(paste(sub$fecha,sub$torneo,sep='|||')))
  data.frame(rama=ga,atleta=a,pais=unname(mapa_pais[a]),
    conservador=if(is.na(rating)) NA_real_ else round(rating-1.96*rd,1),
    rating=rating,rd=rd,combates=nrow(sub),combates_calificables=n_calif,
    torneos=torneos,torneos_con_victoria=length(unique(paste(sub$fecha[sub$resultado=='Victoria'],sub$torneo[sub$resultado=='Victoria'],sep='|||'))),
    victorias=sum(sub$resultado=='Victoria'),derrotas=sum(sub$resultado=='Derrota'),
    estatus=if(is.na(rating)) 'Sin rating' else if(n_calif<10 || torneos<3) 'Provisional' else 'Con historial',
    stringsAsFactors=FALSE)
})
r <- do.call(rbind,ranking)
r <- r[order(r$rama,-r$conservador,na.last=TRUE),]
rownames(r)<-NULL

write.csv(r,file.path(destino,'ranking_conservador_beta31.csv'),row.names=FALSE,fileEncoding='UTF-8',na='')
write.csv(h,file.path(destino,'historial_completo.csv'),row.names=FALSE,fileEncoding='UTF-8',na='')
write.csv(m,file.path(destino,'combates_auditados.csv'),row.names=FALSE,fileEncoding='UTF-8',na='')
write.csv(m[!m$calificable,,drop=FALSE],file.path(destino,'incidencias_para_revision.csv'),row.names=FALSE,fileEncoding='UTF-8',na='')
if(length(incidencias)) write.csv(do.call(rbind,incidencias),file.path(destino,'combates_incompletos.csv'),row.names=FALSE,fileEncoding='UTF-8')
cat('Procesamiento terminado.\nEventos:',length(unique(m$evento)),'\nCombates:',nrow(m),
    '\nAtletas:',nrow(r),'\nCombates calificables:',sum(m$calificable),'\nSalida:',normalizePath(destino),'\n')
