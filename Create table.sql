
-- Projeto: Mieloma Multiplo
-- Banco de Dados: test_4_DBMM


-- Criar o banco de dados
CREATE DATABASE IF NOT EXISTS `test_4_DBMM` 
DEFAULT CHARACTER SET utf8mb4 
DEFAULT COLLATE utf8mb4_0900_ai_ci;

-- Definir o banco de dados 
USE `test_4_DBMM`;

-- Desabilitar temporariamente a verificação de chaves estrangeiras para permitir
-- a exclusão de tabelas em qualquer ordem sem erros.
SET FOREIGN_KEY_CHECKS = 0;

-- Excluir as tabelas se elas já existirem, para garantir um setup limpo
DROP TABLE IF EXISTS `group_multiple_image`;
DROP TABLE IF EXISTS `cell`;
DROP TABLE IF EXISTS `slide_cell_info`;
DROP TABLE IF EXISTS `slide_object`;
DROP TABLE IF EXISTS `slide`;
DROP TABLE IF EXISTS `group_image_info`;
DROP TABLE IF EXISTS `image_metadata`;
DROP TABLE IF EXISTS `patient`;
DROP TABLE IF EXISTS `image_repository`;

-- Reabilita a verificação de chaves estrangeiras
SET FOREIGN_KEY_CHECKS = 1;



-- CRIAÇÃO DAS TABELAS


-- Tabela 1: image_repository
CREATE TABLE `image_repository` (
  `image_repository_id` INT NOT NULL AUTO_INCREMENT,
  `repository_name` VARCHAR(255) NULL COMMENT 'Nome descritivo do repositório de dados.',
  `root_path` VARCHAR(512) NULL COMMENT 'Caminho raiz para o repositório no sistema de arquivos.',
  `require_accesses` TINYINT(1) NOT NULL DEFAULT 1 COMMENT 'Flag booleana (1/0) se o acesso requer credenciais.',
  `type_accesses` VARCHAR(50) NULL COMMENT 'Tipo de acesso (ex: local_filesystem, s3).',
  PRIMARY KEY (`image_repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- Tabela 2: patient
CREATE TABLE `patient` (
  `patient_id` INT NOT NULL AUTO_INCREMENT,
  `label` VARCHAR(255) NULL COMMENT 'Rótulo ou descrição adicional do paciente.',
  `name` VARCHAR(255) NOT NULL COMMENT 'Identificador único e textual do paciente.',
  `number_of_slides` INT NULL COMMENT 'Contagem de lâminas associadas a este paciente.',
  `diagnostic_suspicion` VARCHAR(255) NULL,
  `diagnosis` VARCHAR(255) NULL,
  `prognosis` VARCHAR(255) NULL,
  `multiple_myeloma_diagnose` TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Flag (1/0) para diagnóstico de mieloma múltiplo.',
  PRIMARY KEY (`patient_id`),
  UNIQUE KEY `UQ_patient_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- Tabela 3: image_metadata
CREATE TABLE `image_metadata` (
  `image_metadata_id` INT NOT NULL AUTO_INCREMENT,
  `image_name` VARCHAR(255) NOT NULL COMMENT 'Nome do arquivo com extensão.',
  `image_type` VARCHAR(10) NOT NULL COMMENT 'Extensão do arquivo (ex: jpg, xml, json).',
  `image_date` DATETIME NULL COMMENT 'Data de modificação do arquivo.',
  `image_size_kb` INT NULL COMMENT 'Tamanho do arquivo em Kilobytes.',
  `relative_path` VARCHAR(512) NOT NULL COMMENT 'Caminho relativo e único do arquivo a partir de uma raiz comum.',
  `image_width` INT NULL COMMENT 'Largura da imagem em pixels (apenas para imagens).',
  `image_height` INT NULL COMMENT 'Altura da imagem em pixels (apenas para imagens).',
  `number_of_pixels` BIGINT NULL COMMENT 'Número total de pixels (width * height).',
  PRIMARY KEY (`image_metadata_id`),
  UNIQUE KEY `UQ_relative_path` (`relative_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- Tabela 4: group_image_info
CREATE TABLE `group_image_info` (
  `group_image_info_id` INT NOT NULL AUTO_INCREMENT,
  `description` VARCHAR(255) NULL COMMENT 'Descrição do grupo.',
  `relative_group_path` VARCHAR(512) NULL COMMENT 'Caminho relativo para a pasta que representa o grupo.',
  `image_repository_id` INT NULL,
  PRIMARY KEY (`group_image_info_id`),
  CONSTRAINT `FK_group_image_info_repository` FOREIGN KEY (`image_repository_id`) REFERENCES `image_repository` (`image_repository_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- Tabela 5: slide
CREATE TABLE `slide` (
  `slide_id` INT NOT NULL AUTO_INCREMENT,
  `slide_identifier` VARCHAR(255) NOT NULL COMMENT 'Identificador original da lâmina (nome do arquivo base).',
  `myeloma_is_present` TINYINT(1) NULL COMMENT 'Flag (1/0) indicando presença de mieloma na lâmina.',
  `patient_id` INT NULL,
  `image_metadata_id` INT NULL COMMENT 'FK para a imagem JPG principal desta lâmina.',
  `xml_folder_name` VARCHAR(255) NULL COMMENT 'Nome da pasta original onde o XML da lâmina foi encontrado.',
  `slide_label_content` TEXT NULL,
  PRIMARY KEY (`slide_id`),
  UNIQUE KEY `UQ_slide_identifier` (`slide_identifier`),
  CONSTRAINT `FK_slide_patient` FOREIGN KEY (`patient_id`) REFERENCES `patient` (`patient_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `FK_slide_image_metadata` FOREIGN KEY (`image_metadata_id`) REFERENCES `image_metadata` (`image_metadata_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- Tabela 6: slide_object
CREATE TABLE `slide_object` (
  `slide_object_id` INT NOT NULL AUTO_INCREMENT,
  `slide_id` INT NOT NULL,
  `object_identifier_str` VARCHAR(255) NULL COMMENT 'ID original do objeto no arquivo XML.',
  `object_name` VARCHAR(100) NULL COMMENT 'Nome/classe do objeto (ex: PLASMOCITO).',
  `xmin` INT NULL,
  `ymin` INT NULL,
  `xmax` INT NULL,
  `ymax` INT NULL,
  `pose` VARCHAR(50) NULL,
  `truncated` TINYINT(1) NULL,
  `difficult` TINYINT(1) NULL,
  PRIMARY KEY (`slide_object_id`),
  CONSTRAINT `FK_slide_object_slide` FOREIGN KEY (`slide_id`) REFERENCES `slide` (`slide_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- Tabela 7: slide_cell_info
CREATE TABLE `slide_cell_info` (
  `slide_cell_info_id` INT NOT NULL AUTO_INCREMENT,
  `slide_id` INT NOT NULL COMMENT 'FK para a tabela slide, estabelecendo uma relação 1-para-1.',
  `calculated_cell_count` INT NULL COMMENT 'Contagem total de células (plasma + non-plasma) para esta lâmina.',
  `other_notes` VARCHAR(255) NULL,
  PRIMARY KEY (`slide_cell_info_id`),
  UNIQUE KEY `UQ_slide_id` (`slide_id`),
  CONSTRAINT `FK_slide_cell_info_slide` FOREIGN KEY (`slide_id`) REFERENCES `slide` (`slide_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- Tabela 8: cell
CREATE TABLE `cell` (
  `cell_id` INT NOT NULL AUTO_INCREMENT,
  `cell_identifier_str` VARCHAR(255) NOT NULL COMMENT 'Identificador original da célula (nome do arquivo base).',
  `slide_cell_info_id` INT NOT NULL,
  `image_metadata_id` INT NULL COMMENT 'FK para os metadados da imagem JPG desta célula.',
  `cell_type` VARCHAR(50) NULL COMMENT 'Tipo da célula (plasma ou non-plasma).',
  `mask_label` VARCHAR(100) NULL COMMENT 'Label da máscara vindo do JSON.',
  `mask_shape_type` VARCHAR(50) NULL COMMENT 'Tipo da forma da máscara (ex: polygon).',
  `mask_points_json_str` TEXT NULL COMMENT 'Pontos do polígono da máscara armazenados como string JSON.',
  `core_numbers` INT NULL,
  PRIMARY KEY (`cell_id`),
  UNIQUE KEY `UQ_cell_identifier_str` (`cell_identifier_str`),
  CONSTRAINT `FK_cell_slide_cell_info` FOREIGN KEY (`slide_cell_info_id`) REFERENCES `slide_cell_info` (`slide_cell_info_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_cell_image_metadata` FOREIGN KEY (`image_metadata_id`) REFERENCES `image_metadata` (`image_metadata_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- Tabela 9: group_multiple_image
CREATE TABLE `group_multiple_image` (
  `group_multiple_image_id` INT NOT NULL AUTO_INCREMENT,
  `group_image_info_id` INT NOT NULL,
  `image_metadata_id` INT NOT NULL,
  PRIMARY KEY (`group_multiple_image_id`),
  CONSTRAINT `FK_group_multiple_image_group` FOREIGN KEY (`group_image_info_id`) REFERENCES `group_image_info` (`group_image_info_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_group_multiple_image_metadata` FOREIGN KEY (`image_metadata_id`) REFERENCES `image_metadata` (`image_metadata_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;