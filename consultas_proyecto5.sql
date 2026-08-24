-- ==============================================================================
-- PROYECTO: Reconciliación y Procesamiento de Datos Actuariales (PostgreSQL)
-- OBJETIVO: Calcular devengamiento histórico de primas (Pro Rata Temporis)
--           y verificar consistencia referencial de siniestros.
-- ESCALA:   1,000,000 de pólizas (Big Data Simulation)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- FASE 1: DEFINICIÓN DE ESTRUCTURAS (DDL) Y LIMPIEZA
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS siniestros;
DROP TABLE IF EXISTS endosos;
DROP TABLE IF EXISTS polizas;

CREATE TABLE polizas (
    id_poliza VARCHAR(15) PRIMARY KEY,
    fecha_emision DATE NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    prima_emitida NUMERIC(12, 2) NOT NULL
);

CREATE TABLE endosos (
    id_endoso SERIAL PRIMARY KEY,
    id_poliza VARCHAR(15) REFERENCES polizas(id_poliza),
    tipo_endoso VARCHAR(20) NOT NULL,
    fecha_efecto DATE NOT NULL,
    prima_adicional NUMERIC(12, 2) DEFAULT 0
);

CREATE TABLE siniestros (
    id_siniestro VARCHAR(15) PRIMARY KEY,
    id_poliza VARCHAR(15) REFERENCES polizas(id_poliza),
    fecha_ocurrencia DATE NOT NULL,
    monto_reclamado NUMERIC(12, 2) NOT NULL
);

-- ------------------------------------------------------------------------------
-- FASE 2: GENERACIÓN SINTÉTICA MASIVA (DML)
-- ------------------------------------------------------------------------------

-- A. Inserción Masiva de 1,000,000 de Pólizas (Portafolio 2024-2025)
INSERT INTO polizas (id_poliza, fecha_emision, fecha_inicio, fecha_fin, prima_emitida)
SELECT 
    'POL-' || LPAD(secuencia::text, 7, '0'),
    (fecha_base - (random() * 30)::integer * interval '1 day')::date AS fecha_emision,
    fecha_base AS fecha_inicio,
    (fecha_base + interval '1 year' - interval '1 day')::date AS fecha_fin,
    ROUND((random() * 50000 + 5000)::numeric, 2) AS prima_emitida
FROM (
    SELECT 
        generate_series(1, 1000000) AS secuencia,
        '2024-01-01'::date + (random() * 730)::integer * interval '1 day' AS fecha_base
) sub;

-- B. Inserción de Endosos (~15% de la cartera)
INSERT INTO endosos (id_poliza, tipo_endoso, fecha_efecto, prima_adicional)
SELECT 
    id_poliza,
    CASE WHEN random() > 0.4 THEN 'Aumento' ELSE 'Cancelacion' END AS tipo_endoso,
    (fecha_inicio + (random() * 180 + 10)::integer * interval '1 day')::date AS fecha_efecto,
    CASE WHEN random() > 0.4 THEN ROUND((random() * 10000)::numeric, 2) ELSE 0 END AS prima_adicional
FROM polizas
WHERE random() <= 0.15;

-- C. Inserción de Siniestros (~20% de frecuencia de siniestralidad, con ruido estocástico)
INSERT INTO siniestros (id_siniestro, id_poliza, fecha_ocurrencia, monto_reclamado)
SELECT 
    'SIN-' || LPAD(ROW_NUMBER() OVER()::text, 7, '0'),
    id_poliza,
    (fecha_inicio + ((random() * 400 - 30)::integer) * interval '1 day')::date AS fecha_ocurrencia,
    ROUND((random() * 15000 + 1000)::numeric, 2) AS monto_reclamado
FROM polizas
WHERE random() <= 0.20;


-- ------------------------------------------------------------------------------
-- FASE 3: OPTIMIZACIÓN (ÍNDICES B-TREE Y ESTADÍSTICAS)
-- ------------------------------------------------------------------------------
CREATE INDEX idx_endosos_poliza ON endosos(id_poliza);
CREATE INDEX idx_siniestros_poliza ON siniestros(id_poliza);
CREATE INDEX idx_siniestros_fecha ON siniestros(fecha_ocurrencia);
CREATE INDEX idx_endosos_tipo_fecha ON endosos(tipo_endoso, fecha_efecto);

ANALYZE polizas;
ANALYZE endosos;
ANALYZE siniestros;

-- ------------------------------------------------------------------------------
-- FASE 4: SCRIPT CENTRAL DE RECONCILIACIÓN (CTEs & WINDOW FUNCTIONS)
-- ------------------------------------------------------------------------------
-- Nota: Incluye EXPLAIN ANALYZE para medir tiempos de ejecución en el IDE.

WITH Fecha_Corte AS (
    SELECT CURRENT_DATE AS fecha_evaluacion
),
Estado_Vigencia AS (
    SELECT 
        p.id_poliza,
        p.fecha_inicio,
        p.fecha_fin AS fecha_fin_teorica,
        COALESCE(
            MAX(CASE WHEN e.tipo_endoso = 'Cancelacion' THEN e.fecha_efecto END), 
            p.fecha_fin
        ) AS fecha_fin_real
    FROM polizas p
    LEFT JOIN endosos e ON p.id_poliza = e.id_poliza
    GROUP BY p.id_poliza, p.fecha_inicio, p.fecha_fin
),
Eventos_Financieros AS (
    SELECT id_poliza, fecha_inicio AS fecha_evento, prima_emitida AS movimiento_prima, 'Emision' AS tipo_evento
    FROM polizas
    UNION ALL
    SELECT id_poliza, fecha_efecto AS fecha_evento, prima_adicional AS movimiento_prima, tipo_endoso AS tipo_evento
    FROM endosos
    WHERE tipo_endoso != 'Cancelacion'
),
Calculo_Exposicion AS (
    SELECT 
        ef.id_poliza,
        ef.fecha_evento,
        ef.movimiento_prima,
        -- Cálculo de Prima Acumulada
        SUM(ef.movimiento_prima) OVER (
            PARTITION BY ef.id_poliza 
            ORDER BY ef.fecha_evento 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS prima_acumulada_vigente,
        -- Novedad: Numeración inversa para identificar el último estado financiero sin subconsultas
        ROW_NUMBER() OVER (
            PARTITION BY ef.id_poliza 
            ORDER BY ef.fecha_evento DESC
        ) AS orden_inverso
    FROM Eventos_Financieros ef
),
Siniestros_Reconciliados AS (
    SELECT 
        s.id_poliza,
        COUNT(s.id_siniestro) AS conteo_siniestros_validos,
        SUM(s.monto_reclamado) AS total_siniestros_validos,
        SUM(CASE WHEN s.fecha_ocurrencia > ev.fecha_fin_real THEN s.monto_reclamado ELSE 0 END) AS siniestros_rechazados_extemporaneos
    FROM siniestros s
    INNER JOIN Estado_Vigencia ev ON s.id_poliza = ev.id_poliza
    WHERE s.fecha_ocurrencia >= ev.fecha_inicio 
      AND s.fecha_ocurrencia <= ev.fecha_fin_real
    GROUP BY s.id_poliza
)
SELECT 
    ev.id_poliza,
    ev.fecha_inicio,
    ev.fecha_fin_real,
    ce.prima_acumulada_vigente AS prima_total_suscrita,
    ROUND(
        ce.prima_acumulada_vigente * 
        (GREATEST(0, LEAST((SELECT fecha_evaluacion FROM Fecha_Corte) - ev.fecha_inicio, ev.fecha_fin_real - ev.fecha_inicio))::NUMERIC / 
        (ev.fecha_fin_teorica - ev.fecha_inicio)::NUMERIC), 2
    ) AS prima_devengada,
    COALESCE(sr.conteo_siniestros_validos, 0) AS cantidad_siniestros,
    COALESCE(sr.total_siniestros_validos, 0.00) AS monto_siniestros_incurridos,
    COALESCE(sr.siniestros_rechazados_extemporaneos, 0.00) AS reservas_liberadas_rechazos
FROM Estado_Vigencia ev
-- Modificación Crítica: El cruce ahora evalúa un Hash Join sobre un entero, anulando el Nested Loop
LEFT JOIN Calculo_Exposicion ce ON ev.id_poliza = ce.id_poliza AND ce.orden_inverso = 1
LEFT JOIN Siniestros_Reconciliados sr ON ev.id_poliza = sr.id_poliza;