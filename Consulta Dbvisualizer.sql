-- CONSULTAS SQL OTIMIZADAS PARA test_4_DBMM
-- Projeto: Mieloma Múltiplo - Análise de Aspirados de Medula Óssea

-- BLOCO 1: VERIFICAÇÕES BÁSICAS DE INTEGRIDADE

-- CONSULTA 1.1: Verificar se há lâminas sem paciente
-- OBJETIVO: Detectar problemas de integridade referencial - lâminas que perderam o vínculo com pacientes
USE `test_4_DBMM`;
SELECT 
    s.slide_id AS 'ID da Lâmina',
    s.slide_identifier AS 'Nome da Lâmina',
    'SEM PACIENTE ASSOCIADO' AS 'Status'
FROM slide s
LEFT JOIN patient p ON s.patient_id = p.patient_id
WHERE p.patient_id IS NULL
ORDER BY s.slide_id;

-- CONSULTA 1.2: Verificar se há lâminas sem células (plasmáticas ou não-plasmáticas)
-- OBJETIVO: Identificar lâminas que não possuem células associadas, o que pode indicar problemas na importação
-- COMO FUNCIONA: Navega slide → slide_cell_info → cell e detecta lâminas vazias
USE `test_4_DBMM`;
SELECT 
    s.slide_id AS 'ID da Lâmina',
    s.slide_identifier AS 'Nome da Lâmina',
    p.name AS 'Paciente',
    'SEM CÉLULAS ASSOCIADAS' AS 'Status',
    COALESCE(sci.calculated_cell_count, 0) AS 'Contagem Calculada'
FROM slide s
LEFT JOIN patient p ON s.patient_id = p.patient_id
LEFT JOIN slide_cell_info sci ON s.slide_id = sci.slide_id
LEFT JOIN cell c ON sci.slide_cell_info_id = c.slide_cell_info_id
GROUP BY s.slide_id, s.slide_identifier, p.name, sci.calculated_cell_count
HAVING COUNT(c.cell_id) = 0  -- Lâminas sem nenhuma célula
ORDER BY p.name, s.slide_identifier;

-- CONSULTA 1.3: Verificar integridade da hierarquia Pacientes → Lâminas → Células
-- OBJETIVO: Avaliar se a relação hierárquica está consistente em todo o banco
-- COMO FUNCIONA: Conta registros em cada nível e detecta quebras na hierarquia
USE `test_4_DBMM`;
SELECT 
    p.name AS 'Paciente',
    COUNT(DISTINCT s.slide_id) AS 'Lâminas Associadas',
    COUNT(DISTINCT sci.slide_cell_info_id) AS 'Slide_Cell_Info Associados',
    COUNT(DISTINCT c.cell_id) AS 'Células Associadas',
    -- Verificações de integridade
    CASE 
        WHEN COUNT(DISTINCT s.slide_id) = 0 THEN 'PACIENTE SEM LÂMINAS'
        WHEN COUNT(DISTINCT sci.slide_cell_info_id) < COUNT(DISTINCT s.slide_id) THEN 'LÂMINAS SEM SLIDE_CELL_INFO'
        WHEN COUNT(DISTINCT c.cell_id) = 0 THEN 'PACIENTE SEM CÉLULAS'
        ELSE 'HIERARQUIA OK'
    END AS 'Status da Hierarquia'
FROM patient p
LEFT JOIN slide s ON p.patient_id = s.patient_id
LEFT JOIN slide_cell_info sci ON s.slide_id = sci.slide_id
LEFT JOIN cell c ON sci.slide_cell_info_id = c.slide_cell_info_id
GROUP BY p.patient_id, p.name
ORDER BY p.name;

-- CONSULTA 1.4:  Contar registros e volume de dados em cada tabela principal.
-- OBJETIVO: Verificar o volume total de dados e o armazenamento ocupado pelas imagens associadas.
SELECT
    'Pacientes' AS 'Tabela',
    COUNT(*) AS 'Total de Registros',
    NULL AS 'Tamanho Total (KB)' -- Pacientes não têm imagens diretamente associadas
FROM patient

UNION ALL

SELECT
    'Lâminas' AS 'Tabela',
    COUNT(s.slide_id) AS 'Total de Registros',
    -- Soma apenas o tamanho das imagens JPG das lâminas
    SUM(CASE WHEN im.image_type = 'jpg' THEN im.image_size_kb ELSE 0 END) AS 'Tamanho Total (KB)'
FROM slide s
LEFT JOIN image_metadata im ON s.image_metadata_id = im.image_metadata_id

UNION ALL

SELECT
    'Células' AS 'Tabela',
    COUNT(c.cell_id) AS 'Total de Registros',
    -- Soma apenas o tamanho das imagens JPG das células
    SUM(CASE WHEN im.image_type = 'jpg' THEN im.image_size_kb ELSE 0 END) AS 'Tamanho Total (KB)'
FROM cell c
LEFT JOIN image_metadata im ON c.image_metadata_id = im.image_metadata_id

ORDER BY 'Tabela';

-- BLOCO 2: TESTE DE STRESS

-- CONSULTA 2.1: Análise completa por lâmina com metadados de imagem
-- OBJETIVO: Verificar desempenho do banco com consulta que une todas as tabelas principais
-- TEMPO ESPERADO: 5-30 segundos (dependendo do volume de dados)
USE `test_4_DBMM`;
SELECT 
    p.name AS 'Paciente',
    s.slide_identifier AS 'Lâmina',
    COALESCE(sci.calculated_cell_count, 0) AS 'Células Calculadas',
    COUNT(CASE WHEN c.cell_type = 'plasma' THEN 1 END) AS 'Plasmócitos',
    COUNT(CASE WHEN c.cell_type = 'non-plasma' THEN 1 END) AS 'Não-Plasmócitos',
    CASE 
        WHEN COUNT(c.cell_id) > 0 THEN
            ROUND((COUNT(CASE WHEN c.cell_type = 'plasma' THEN 1 END) * 100.0) / COUNT(c.cell_id), 1)
        ELSE 0 
    END AS '% Plasmócitos',
    COALESCE(im.image_size_kb, 0) AS 'Tamanho Imagem (KB)',
    im.image_date AS 'Data da Imagem'
FROM patient p
JOIN slide s ON p.patient_id = s.patient_id
LEFT JOIN slide_cell_info sci ON s.slide_id = sci.slide_id
LEFT JOIN cell c ON sci.slide_cell_info_id = c.slide_cell_info_id
LEFT JOIN image_metadata im ON s.image_metadata_id = im.image_metadata_id
GROUP BY p.patient_id, s.slide_id
ORDER BY p.name, s.slide_identifier;

-- BLOCO 3: VERIFICAÇÃO DE QUALIDADE DOS DADOS

-- CONSULTA 3.1: Detectar inconsistências entre contagem calculada vs real de células por lâmina
-- OBJETIVO: Identificar discrepâncias entre valor pré-calculado e contagem real no banco
USE `test_4_DBMM`;
SELECT 
    s.slide_identifier AS 'Lâmina com Problema',
    sci.calculated_cell_count AS 'Contagem Calculada',
    COUNT(c.cell_id) AS 'Contagem Real',
    ABS(sci.calculated_cell_count - COUNT(c.cell_id)) AS 'Diferença',
    CASE 
        WHEN ABS(sci.calculated_cell_count - COUNT(c.cell_id)) > 10 THEN 'PROBLEMA GRAVE'
        WHEN ABS(sci.calculated_cell_count - COUNT(c.cell_id)) > 0 THEN 'DIFERENÇA PEQUENA'
        ELSE 'OK'
    END AS 'Status'
FROM slide s
JOIN slide_cell_info sci ON s.slide_id = sci.slide_id
LEFT JOIN cell c ON sci.slide_cell_info_id = c.slide_cell_info_id
GROUP BY s.slide_id
HAVING ABS(sci.calculated_cell_count - COUNT(c.cell_id)) > 0
ORDER BY ABS(sci.calculated_cell_count - COUNT(c.cell_id)) DESC;

-- BLOCO 4: ANÁLISE ESTATÍSTICA BÁSICA

-- CONSULTA 4.1: Estatísticas gerais do dataset
USE `test_4_DBMM`;
SELECT 
    'RESUMO GERAL' AS 'Categoria',
    COUNT(DISTINCT p.patient_id) AS 'Total Pacientes',
    COUNT(DISTINCT s.slide_id) AS 'Total Lâminas',
    COUNT(DISTINCT c.cell_id) AS 'Total Células',
    ROUND(COUNT(DISTINCT s.slide_id) / COUNT(DISTINCT p.patient_id), 2) AS 'Lâminas por Paciente'
FROM patient p
LEFT JOIN slide s ON p.patient_id = s.patient_id
LEFT JOIN slide_cell_info sci ON s.slide_id = sci.slide_id
LEFT JOIN cell c ON sci.slide_cell_info_id = c.slide_cell_info_id;

-- CONSULTA 4.2: Análise GLOBAL de células plasmáticas vs não-plasmáticas
USE `test_4_DBMM`;
SELECT 
    'CÉLULAS PLASMÁTICAS' AS 'Tipo de Célula',
    COUNT(c.cell_id) AS 'Quantidade Total',
    ROUND(
        (COUNT(c.cell_id) * 100.0) / 
        (SELECT COUNT(*) FROM cell WHERE cell_type IN ('plasma', 'non-plasma')), 2
    ) AS 'Percentual Global (%)'
FROM cell c
WHERE c.cell_type = 'plasma'

UNION ALL

SELECT 
    'CÉLULAS NÃO-PLASMÁTICAS' AS 'Tipo de Célula',
    COUNT(c.cell_id) AS 'Quantidade Total',
    ROUND(
        (COUNT(c.cell_id) * 100.0) / 
        (SELECT COUNT(*) FROM cell WHERE cell_type IN ('plasma', 'non-plasma')), 2
    ) AS 'Percentual Global (%)'
FROM cell c
WHERE c.cell_type = 'non-plasma'

UNION ALL

SELECT 
    'TOTAL GERAL' AS 'Tipo de Célula',
    COUNT(c.cell_id) AS 'Quantidade Total',
    100.00 AS 'Percentual Global (%)'
FROM cell c
WHERE c.cell_type IN ('plasma', 'non-plasma');

-- CONSULTA 4.3: Análise POR LÂMINA - Células plasmáticas vs não-plasmáticas
USE `test_4_DBMM`;
SELECT 
    p.name AS 'Paciente',
    s.slide_identifier AS 'Lâmina',
    COUNT(c.cell_id) AS 'Total Células',
    COUNT(CASE WHEN c.cell_type = 'plasma' THEN 1 END) AS 'Plasmócitos',
    COUNT(CASE WHEN c.cell_type = 'non-plasma' THEN 1 END) AS 'Não-Plasmócitos',
    CASE 
        WHEN COUNT(c.cell_id) > 0 THEN
            ROUND((COUNT(CASE WHEN c.cell_type = 'plasma' THEN 1 END) * 100.0) / COUNT(c.cell_id), 2)
        ELSE 0 
    END AS '% Plasmócitos',
    CASE 
        WHEN COUNT(c.cell_id) > 0 THEN
            ROUND((COUNT(CASE WHEN c.cell_type = 'non-plasma' THEN 1 END) * 100.0) / COUNT(c.cell_id), 2)
        ELSE 0 
    END AS '% Não-Plasmócitos'
FROM patient p
JOIN slide s ON p.patient_id = s.patient_id
LEFT JOIN slide_cell_info sci ON s.slide_id = sci.slide_id
LEFT JOIN cell c ON sci.slide_cell_info_id = c.slide_cell_info_id
GROUP BY p.patient_id, s.slide_id
ORDER BY p.name, s.slide_identifier;

-- CONSULTA 4.4: Estatísticas POR PACIENTE
USE `test_4_DBMM`;
SELECT 
    p.name AS 'Paciente',
    COUNT(DISTINCT s.slide_id) AS 'Número de Lâminas',
    COUNT(DISTINCT c.cell_id) AS 'Total de Células',
    COUNT(DISTINCT CASE WHEN c.cell_type = 'plasma' THEN c.cell_id END) AS 'Total Plasmócitos',
    COUNT(DISTINCT CASE WHEN c.cell_type = 'non-plasma' THEN c.cell_id END) AS 'Total Não-Plasmócitos',
    CASE 
        WHEN COUNT(DISTINCT c.cell_id) > 0 THEN
            ROUND((COUNT(DISTINCT CASE WHEN c.cell_type = 'plasma' THEN c.cell_id END) * 100.0) / COUNT(DISTINCT c.cell_id), 2)
        ELSE 0 
    END AS '% Plasmócitos do Paciente',
    ROUND(AVG(sci.calculated_cell_count), 2) AS 'Média Células por Lâmina'
FROM patient p
LEFT JOIN slide s ON p.patient_id = s.patient_id
LEFT JOIN slide_cell_info sci ON s.slide_id = sci.slide_id
LEFT JOIN cell c ON sci.slide_cell_info_id = c.slide_cell_info_id
GROUP BY p.patient_id, p.name
ORDER BY p.name;

-- CONSULTA 4.5: Evolução temporal da proporção de células plasmáticas por paciente
-- OBJETIVO: Analisar como a proporção de plasmócitos varia ao longo do tempo para cada paciente
-- COMO FUNCIONA: Ordena as lâminas por data de imagem e calcula a proporção cronologicamente
USE `test_4_DBMM`;
SELECT 
    p.name AS 'Paciente',
    s.slide_identifier AS 'Lâmina',
    im.image_date AS 'Data da Imagem',
    COUNT(c.cell_id) AS 'Total Células',
    COUNT(CASE WHEN c.cell_type = 'plasma' THEN 1 END) AS 'Plasmócitos',
    CASE 
        WHEN COUNT(c.cell_id) > 0 THEN
            ROUND((COUNT(CASE WHEN c.cell_type = 'plasma' THEN 1 END) * 100.0) / COUNT(c.cell_id), 2)
        ELSE 0 
    END AS '% Plasmócitos',
    -- Ranking temporal das lâminas por paciente (1 = mais antiga, n = mais nova)
    ROW_NUMBER() OVER (
        PARTITION BY p.patient_id 
        ORDER BY COALESCE(im.image_date, '1900-01-01')
    ) AS 'Ordem Temporal',
    -- Classificação da lâmina no tempo
    CASE 
        WHEN ROW_NUMBER() OVER (PARTITION BY p.patient_id ORDER BY COALESCE(im.image_date, '1900-01-01')) = 1 
        THEN 'PRIMEIRA LÂMINA'
        WHEN ROW_NUMBER() OVER (PARTITION BY p.patient_id ORDER BY COALESCE(im.image_date, '1900-01-01')) = 
             COUNT(*) OVER (PARTITION BY p.patient_id) 
        THEN 'ÚLTIMA LÂMINA'
        ELSE 'LÂMINA INTERMEDIÁRIA'
    END AS 'Posição Temporal'
FROM patient p
JOIN slide s ON p.patient_id = s.patient_id
LEFT JOIN image_metadata im ON s.image_metadata_id = im.image_metadata_id
LEFT JOIN slide_cell_info sci ON s.slide_id = sci.slide_id
LEFT JOIN cell c ON sci.slide_cell_info_id = c.slide_cell_info_id
GROUP BY p.patient_id, p.name, s.slide_id, s.slide_identifier, im.image_date
ORDER BY p.name, COALESCE(im.image_date, '1900-01-01'), s.slide_identifier;

-- BLOCO 5: ANÁLISE DE IMAGENS

-- CONSULTA 5.1: Estatísticas das imagens microscópicas 
USE `test_4_DBMM`;
SELECT 
    im.image_type AS 'Tipo de Arquivo',
    COUNT(*) AS 'Quantidade',
    ROUND(AVG(im.image_size_kb), 2) AS 'Tamanho Médio (KB)',
    ROUND(SUM(im.image_size_kb)/1024, 2) AS 'Total (MB)',
    ROUND(AVG(im.image_width), 0) AS 'Largura Média',
    ROUND(AVG(im.image_height), 0) AS 'Altura Média',
    MIN(im.image_date) AS 'Imagem Mais Antiga',
    MAX(im.image_date) AS 'Imagem Mais Recente'
FROM image_metadata im
GROUP BY im.image_type
ORDER BY COUNT(*) DESC;

