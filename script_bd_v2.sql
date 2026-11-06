--------------------------------------------------------------------------------
-- UNIVERSIDAD NACIONAL - SEDE REGIONAL BRUNCA
-- ADMINISTRACION DE BASES DE DATOS - II CICLO 2026
-- PROYECTO: BASE DE DATOS PARA UNA CADENA DE NEGOCIOS
-- ENTREGABLE #1 
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- PASO PREVIO: contenedor y usuario de administracion
--------------------------------------------------------------------------------
SET SERVEROUTPUT ON
DECLARE
    v_contenedor VARCHAR2(128);
    v_pdb        VARCHAR2(128);
BEGIN
    v_contenedor := SYS_CONTEXT('USERENV', 'CON_NAME');
    DBMS_OUTPUT.PUT_LINE('Contenedor actual: ' || v_contenedor);

    IF v_contenedor = 'CDB$ROOT' THEN
        BEGIN
            SELECT name INTO v_pdb
              FROM v$pdbs
             WHERE open_mode LIKE 'READ WRITE%'
               AND name <> 'PDB$SEED'
               AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20001,
                    'No hay ningun PDB abierto en modo READ WRITE. Abra uno con: '
                    || 'ALTER PLUGGABLE DATABASE <nombre> OPEN;');
        END;

        EXECUTE IMMEDIATE 'ALTER SESSION SET CONTAINER = ' || v_pdb;
        DBMS_OUTPUT.PUT_LINE('Sesion cambiada al PDB: ' || v_pdb);
    ELSE
        DBMS_OUTPUT.PUT_LINE('La sesion ya esta dentro de un PDB. Se continua.');
    END IF;
END;
/

--------------------------------------------------------------------------------
-- SECCION 1 de 12
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Tablespaces, usuario propietario del esquema y privilegios
--------------------------------------------------------------------------------
-- ALTER SESSION SET CONTAINER = XEPDB1;

SET SERVEROUTPUT ON
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

-- 1. LIMPIEZA PREVIA (idempotencia: permite reejecutar el script completo)
DECLARE
    v_existe NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_existe FROM dba_users WHERE username = 'CADENA_NEG';
    IF v_existe > 0 THEN
        EXECUTE IMMEDIATE 'DROP USER CADENA_NEG CASCADE';
        DBMS_OUTPUT.PUT_LINE('Usuario CADENA_NEG eliminado.');
    END IF;
END;
/

DECLARE
    CURSOR c_tbs IS
        SELECT tablespace_name
          FROM dba_tablespaces
         WHERE tablespace_name IN ('TBS_DATOS', 'TBS_INDICES', 'TBS_AUDITORIA');
BEGIN
    FOR r IN c_tbs LOOP
        EXECUTE IMMEDIATE 'DROP TABLESPACE ' || r.tablespace_name ||
                          ' INCLUDING CONTENTS AND DATAFILES';
        DBMS_OUTPUT.PUT_LINE('Tablespace ' || r.tablespace_name || ' eliminado.');
    END LOOP;
END;
/

WHENEVER SQLERROR EXIT SQL.SQLCODE

-- 2. TABLESPACES
SET SERVEROUTPUT ON
DECLARE
    v_ruta VARCHAR2(512);
    v_arch VARCHAR2(512);
    v_pos  NUMBER;
BEGIN
    SELECT file_name INTO v_arch FROM dba_data_files WHERE ROWNUM = 1;

    v_pos := GREATEST(INSTR(v_arch, '/', -1), INSTR(v_arch, '\\', -1));
    v_ruta := SUBSTR(v_arch, 1, v_pos - 1);

    EXECUTE IMMEDIATE 'ALTER SESSION SET DB_CREATE_FILE_DEST = ''' || v_ruta || '''';
    DBMS_OUTPUT.PUT_LINE('Los datafiles del proyecto se crearan en: ' || v_ruta);
END;
/

CREATE TABLESPACE TBS_DATOS
    DATAFILE SIZE 200M
    AUTOEXTEND ON NEXT 50M MAXSIZE 2G
    EXTENT MANAGEMENT LOCAL AUTOALLOCATE
    SEGMENT SPACE MANAGEMENT AUTO
    LOGGING
    ONLINE;

CREATE TABLESPACE TBS_INDICES
    DATAFILE SIZE 100M
    AUTOEXTEND ON NEXT 25M MAXSIZE 1G
    EXTENT MANAGEMENT LOCAL AUTOALLOCATE
    SEGMENT SPACE MANAGEMENT AUTO
    LOGGING
    ONLINE;

CREATE TABLESPACE TBS_AUDITORIA
    DATAFILE SIZE 100M
    AUTOEXTEND ON NEXT 25M MAXSIZE 1G
    EXTENT MANAGEMENT LOCAL AUTOALLOCATE
    SEGMENT SPACE MANAGEMENT AUTO
    LOGGING
    ONLINE;

-- 3. USUARIO DUENNO DEL ESQUEMA
CREATE USER CADENA_NEG
    IDENTIFIED BY "Cadena2026#"
    DEFAULT TABLESPACE TBS_DATOS
    TEMPORARY TABLESPACE TEMP
    QUOTA UNLIMITED ON TBS_DATOS
    QUOTA UNLIMITED ON TBS_INDICES
    QUOTA UNLIMITED ON TBS_AUDITORIA
    ACCOUNT UNLOCK;

-- 4. PRIVILEGIOS
GRANT CREATE SESSION            TO CADENA_NEG;
GRANT CREATE TABLE              TO CADENA_NEG;
GRANT CREATE VIEW               TO CADENA_NEG;
GRANT CREATE SEQUENCE           TO CADENA_NEG;
GRANT CREATE PROCEDURE          TO CADENA_NEG;
GRANT CREATE TRIGGER            TO CADENA_NEG;
GRANT CREATE SYNONYM            TO CADENA_NEG;
GRANT CREATE TYPE               TO CADENA_NEG;
GRANT CREATE MATERIALIZED VIEW  TO CADENA_NEG;

-- 5. VERIFICACION
SET LINESIZE 200
COLUMN tablespace_name FORMAT A20
COLUMN username        FORMAT A20
COLUMN default_tablespace FORMAT A20

PROMPT
PROMPT === TABLESPACES CREADOS ===
SELECT tablespace_name, status, contents, extent_management, segment_space_management
  FROM dba_tablespaces
 WHERE tablespace_name LIKE 'TBS_%'
 ORDER BY tablespace_name;

PROMPT
PROMPT === USUARIO CREADO ===
SELECT username, default_tablespace, temporary_tablespace, account_status
  FROM dba_users
 WHERE username = 'CADENA_NEG';

PROMPT
PROMPT === CUOTAS ASIGNADAS ===
SELECT tablespace_name, username, max_bytes
  FROM dba_ts_quotas
 WHERE username = 'CADENA_NEG'
 ORDER BY tablespace_name;

PROMPT
PROMPT Infraestructura creada correctamente.
PROMPT Se continua con la creacion de objetos en el esquema CADENA_NEG
PROMPT

--------------------------------------------------------------------------------
-- Los objetos siguientes se crean en el esquema CADENA_NEG
--------------------------------------------------------------------------------
ALTER SESSION SET CURRENT_SCHEMA = CADENA_NEG;


--------------------------------------------------------------------------------
-- SECCION 2 de 12: modulo CAT_
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Jerarquia geografica
--------------------------------------------------------------------------------
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SECUENCIAS DEL MODULO
CREATE SEQUENCE SEQ_CAT_PAIS      START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_CAT_PROVINCIA  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_CAT_CANTON    START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_CAT_DISTRITO  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- TABLA: CAT_PAIS
CREATE TABLE CAT_PAIS (
    ID_PAIS              NUMBER(10)    DEFAULT SEQ_CAT_PAIS.NEXTVAL NOT NULL,
    CODIGO_ISO_PAIS      VARCHAR2(3)   NOT NULL,
    NOMBRE_PAIS          VARCHAR2(50)  NOT NULL,
    COD_TELEFONICO_PAIS  VARCHAR2(5),
    ESTADO_PAIS          VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_PAIS    VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_PAIS      TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PAIS     VARCHAR2(30),
    FECHA_MOD_PAIS       TIMESTAMP,
    CONSTRAINT PK_PAIS PRIMARY KEY (ID_PAIS)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT UK_PAIS_CODIGO_ISO UNIQUE (CODIGO_ISO_PAIS)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT UK_PAIS_NOMBRE UNIQUE (NOMBRE_PAIS)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_PAIS_ESTADO CHECK (ESTADO_PAIS IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  CAT_PAIS                      IS 'Catalogo de paises. Se usa para nacionalidad, residencia y ubicacion geografica.';
COMMENT ON COLUMN CAT_PAIS.ID_PAIS              IS 'Identificador unico del pais.';
COMMENT ON COLUMN CAT_PAIS.CODIGO_ISO_PAIS      IS 'Codigo ISO 3166-1 alfa-3 del pais. Ejemplo: CRI.';
COMMENT ON COLUMN CAT_PAIS.NOMBRE_PAIS          IS 'Nombre oficial del pais.';
COMMENT ON COLUMN CAT_PAIS.COD_TELEFONICO_PAIS  IS 'Prefijo telefonico internacional sin el signo mas. Ejemplo: 506.';
COMMENT ON COLUMN CAT_PAIS.ESTADO_PAIS          IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN CAT_PAIS.USUARIO_CREA_PAIS    IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN CAT_PAIS.FECHA_CREA_PAIS      IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN CAT_PAIS.USUARIO_MOD_PAIS     IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN CAT_PAIS.FECHA_MOD_PAIS       IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: CAT_PROVINCIA
CREATE TABLE CAT_PROVINCIA (
    ID_PROVINCIA        NUMBER(10)    DEFAULT SEQ_CAT_PROVINCIA.NEXTVAL NOT NULL,
    ID_PAIS             NUMBER(10)    NOT NULL,
    CODIGO_PROVI        VARCHAR2(10)  NOT NULL,
    NOMBRE_PROVI        VARCHAR2(50)  NOT NULL,
    ESTADO_PROVI        VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_PROVI  VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_PROVI    TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PROVI   VARCHAR2(30),
    FECHA_MOD_PROVI     TIMESTAMP,
    CONSTRAINT PK_PROVI PRIMARY KEY (ID_PROVINCIA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_PROVI_PAIS FOREIGN KEY (ID_PAIS)
        REFERENCES CAT_PAIS (ID_PAIS),
    CONSTRAINT UK_PROVI_PAIS_COD UNIQUE (ID_PAIS, CODIGO_PROVI)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_PROVI_ESTADO CHECK (ESTADO_PROVI IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  CAT_PROVINCIA                     IS 'Division politica de primer nivel dentro de un pais.';
COMMENT ON COLUMN CAT_PROVINCIA.ID_PROVINCIA        IS 'Identificador unico de la provincia.';
COMMENT ON COLUMN CAT_PROVINCIA.ID_PAIS             IS 'Pais al que pertenece la provincia. FK a CAT_PAIS.';
COMMENT ON COLUMN CAT_PROVINCIA.CODIGO_PROVI        IS 'Codigo oficial de la provincia, unico dentro del pais.';
COMMENT ON COLUMN CAT_PROVINCIA.NOMBRE_PROVI        IS 'Nombre de la provincia.';
COMMENT ON COLUMN CAT_PROVINCIA.ESTADO_PROVI        IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN CAT_PROVINCIA.USUARIO_CREA_PROVI  IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN CAT_PROVINCIA.FECHA_CREA_PROVI    IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN CAT_PROVINCIA.USUARIO_MOD_PROVI   IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN CAT_PROVINCIA.FECHA_MOD_PROVI     IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: CAT_CANTON
CREATE TABLE CAT_CANTON (
    ID_CANTON          NUMBER(10)    DEFAULT SEQ_CAT_CANTON.NEXTVAL NOT NULL,
    ID_PROVINCIA       NUMBER(10)    NOT NULL,
    CODIGO_CANT        VARCHAR2(10)  NOT NULL,
    NOMBRE_CANT        VARCHAR2(50)  NOT NULL,
    ESTADO_CANT        VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_CANT  VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_CANT    TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_CANT   VARCHAR2(30),
    FECHA_MOD_CANT     TIMESTAMP,
    CONSTRAINT PK_CANT PRIMARY KEY (ID_CANTON)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_CANT_PROVI FOREIGN KEY (ID_PROVINCIA)
        REFERENCES CAT_PROVINCIA (ID_PROVINCIA),
    CONSTRAINT UK_CANT_PROVI_COD UNIQUE (ID_PROVINCIA, CODIGO_CANT)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_CANT_ESTADO CHECK (ESTADO_CANT IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  CAT_CANTON                    IS 'Division politica de segundo nivel, dependiente de una provincia.';
COMMENT ON COLUMN CAT_CANTON.ID_CANTON          IS 'Identificador unico del canton.';
COMMENT ON COLUMN CAT_CANTON.ID_PROVINCIA       IS 'Provincia a la que pertenece el canton. FK a CAT_PROVINCIA.';
COMMENT ON COLUMN CAT_CANTON.CODIGO_CANT        IS 'Codigo oficial del canton, unico dentro de la provincia.';
COMMENT ON COLUMN CAT_CANTON.NOMBRE_CANT        IS 'Nombre del canton.';
COMMENT ON COLUMN CAT_CANTON.ESTADO_CANT        IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN CAT_CANTON.USUARIO_CREA_CANT  IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN CAT_CANTON.FECHA_CREA_CANT    IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN CAT_CANTON.USUARIO_MOD_CANT   IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN CAT_CANTON.FECHA_MOD_CANT     IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: CAT_DISTRITO
CREATE TABLE CAT_DISTRITO (
    ID_DISTRITO         NUMBER(10)    DEFAULT SEQ_CAT_DISTRITO.NEXTVAL NOT NULL,
    ID_CANTON           NUMBER(10)    NOT NULL,
    CODIGO_DIST         VARCHAR2(10)  NOT NULL,
    NOMBRE_DIST         VARCHAR2(50)  NOT NULL,
    CODIGO_POSTAL_DIST  VARCHAR2(10),
    ESTADO_DIST         VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_DIST   VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_DIST     TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_DIST    VARCHAR2(30),
    FECHA_MOD_DIST      TIMESTAMP,
    CONSTRAINT PK_DIST PRIMARY KEY (ID_DISTRITO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_DIST_CANT FOREIGN KEY (ID_CANTON)
        REFERENCES CAT_CANTON (ID_CANTON),
    CONSTRAINT UK_DIST_CANT_COD UNIQUE (ID_CANTON, CODIGO_DIST)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_DIST_ESTADO CHECK (ESTADO_DIST IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  CAT_DISTRITO                     IS 'Division politica de tercer nivel. Es el nivel al que se amarra toda direccion fisica del sistema.';
COMMENT ON COLUMN CAT_DISTRITO.ID_DISTRITO         IS 'Identificador unico del distrito.';
COMMENT ON COLUMN CAT_DISTRITO.ID_CANTON           IS 'Canton al que pertenece el distrito. FK a CAT_CANTON.';
COMMENT ON COLUMN CAT_DISTRITO.CODIGO_DIST         IS 'Codigo oficial del distrito, unico dentro del canton.';
COMMENT ON COLUMN CAT_DISTRITO.NOMBRE_DIST         IS 'Nombre del distrito.';
COMMENT ON COLUMN CAT_DISTRITO.CODIGO_POSTAL_DIST  IS 'Codigo postal del distrito. Es el unico lugar donde se guarda el codigo postal.';
COMMENT ON COLUMN CAT_DISTRITO.ESTADO_DIST         IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN CAT_DISTRITO.USUARIO_CREA_DIST   IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN CAT_DISTRITO.FECHA_CREA_DIST     IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN CAT_DISTRITO.USUARIO_MOD_DIST    IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN CAT_DISTRITO.FECHA_MOD_DIST      IS 'Fecha y hora de la ultima modificacion.';

PROMPT Modulo CAT_ creado: 4 tablas, 4 secuencias.


--------------------------------------------------------------------------------
-- SECCION 3 de 12: modulo PER_
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Personas, clientes y proveedores
--------------------------------------------------------------------------------
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SECUENCIAS DEL MODULO
CREATE SEQUENCE SEQ_PER_PERSONA          START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PER_PERSONA_FISICA   START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PER_PERSONA_JURIDICA  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PER_DIRECCION        START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PER_CONTACTO         START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PER_CLIENTE          START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PER_PROVEEDOR        START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- TABLA: PER_PERSONA
CREATE TABLE PER_PERSONA (
    ID_PERSONA               NUMBER(10)    DEFAULT SEQ_PER_PERSONA.NEXTVAL NOT NULL,
    TIPO_PERS                VARCHAR2(1)   NOT NULL,
    NUM_IDENTIFICACION_PERS  VARCHAR2(30)  NOT NULL,
    FECHA_REGISTRO_PERS      DATE          DEFAULT SYSDATE NOT NULL,
    ESTADO_PERS              VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_PERS        VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_PERS          TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PERS         VARCHAR2(30),
    FECHA_MOD_PERS           TIMESTAMP,
    CONSTRAINT PK_PERS PRIMARY KEY (ID_PERSONA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT UK_PERS_IDENTIFICACION UNIQUE (TIPO_PERS, NUM_IDENTIFICACION_PERS)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT UK_PERS_TIPO UNIQUE (ID_PERSONA, TIPO_PERS)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_PERS_TIPO CHECK (TIPO_PERS IN ('N','E','J')),
    CONSTRAINT CK_PERS_FORMATO_IDENT CHECK (
            (TIPO_PERS = 'N' AND REGEXP_LIKE(NUM_IDENTIFICACION_PERS, '^[1-9][0-9]{8}$'))
            OR (TIPO_PERS = 'J' AND REGEXP_LIKE(NUM_IDENTIFICACION_PERS, '^[0-9]{10}$'))
            OR (TIPO_PERS = 'E' AND LENGTH(NUM_IDENTIFICACION_PERS) >= 5)
        ),
    CONSTRAINT CK_PERS_ESTADO CHECK (ESTADO_PERS IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PER_PERSONA                          IS 'Supertipo de toda persona fisica o juridica conocida por el sistema (clientes, proveedores, usuarios, la propia empresa).';
COMMENT ON COLUMN PER_PERSONA.ID_PERSONA               IS 'Identificador unico de la persona.';
COMMENT ON COLUMN PER_PERSONA.TIPO_PERS                IS 'Tipo de persona: N=Nacional, E=Extranjero, J=Empresa (juridica). Es el discriminador de los subtipos.';
COMMENT ON COLUMN PER_PERSONA.NUM_IDENTIFICACION_PERS  IS 'Cedula, DIMEX, pasaporte o cedula juridica. Longitud variable porque las cedulas de extranjeros varian de tipo y tamano.';
COMMENT ON COLUMN PER_PERSONA.FECHA_REGISTRO_PERS      IS 'Fecha en que la persona se registro en el sistema.';
COMMENT ON COLUMN PER_PERSONA.ESTADO_PERS              IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PER_PERSONA.USUARIO_CREA_PERS        IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PER_PERSONA.FECHA_CREA_PERS          IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PER_PERSONA.USUARIO_MOD_PERS         IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PER_PERSONA.FECHA_MOD_PERS           IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PER_PERSONA_FISICA
CREATE TABLE PER_PERSONA_FISICA (
    ID_PERSONA_FISICA      NUMBER(10)     NOT NULL,
    TIPO_PERS              VARCHAR2(1)    DEFAULT 'N' NOT NULL,
    NOMBRE_PEFI            VARCHAR2(40)   NOT NULL,
    APELLIDO1_PEFI         VARCHAR2(40)   NOT NULL,
    APELLIDO2_PEFI         VARCHAR2(40),
    SEXO_PEFI              VARCHAR2(1)    NOT NULL,
    FECHA_NACIMIENTO_PEFI  DATE           NOT NULL,
    ESTADO_CIVIL_PEFI      VARCHAR2(1),
    ESCOLARIDAD_PEFI       VARCHAR2(1),
    ID_PAIS_NACIONALIDAD   NUMBER(10)     NOT NULL,
    ID_PAIS_RESIDENCIA     NUMBER(10)     NOT NULL,
    PUESTO_PEFI            VARCHAR2(100),
    EMPRESA_LABORA_PEFI    VARCHAR2(150),
    ES_ASEGURADO_PEFI      VARCHAR2(1)    DEFAULT 'N' NOT NULL,
    USUARIO_CREA_PEFI      VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_PEFI        TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PEFI       VARCHAR2(30),
    FECHA_MOD_PEFI         TIMESTAMP,
    CONSTRAINT PK_PEFI PRIMARY KEY (ID_PERSONA_FISICA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_PEFI_PERS FOREIGN KEY (ID_PERSONA_FISICA, TIPO_PERS)
        REFERENCES PER_PERSONA (ID_PERSONA, TIPO_PERS),
    CONSTRAINT FK_PEFI_PAIS_NAC FOREIGN KEY (ID_PAIS_NACIONALIDAD)
        REFERENCES CAT_PAIS (ID_PAIS),
    CONSTRAINT FK_PEFI_PAIS_RES FOREIGN KEY (ID_PAIS_RESIDENCIA)
        REFERENCES CAT_PAIS (ID_PAIS),
    CONSTRAINT CK_PEFI_TIPO CHECK (TIPO_PERS IN ('N','E')),
    CONSTRAINT CK_PEFI_SEXO CHECK (SEXO_PEFI IN ('M','F','O')),
    CONSTRAINT CK_PEFI_ESTADO_CIVIL CHECK (ESTADO_CIVIL_PEFI IN ('S','C','D','V','U')),
    CONSTRAINT CK_PEFI_ESCOLARIDAD CHECK (ESCOLARIDAD_PEFI IN ('N','P','S','T','U','G')),
    CONSTRAINT CK_PEFI_ASEGURADO CHECK (ES_ASEGURADO_PEFI IN ('S','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PER_PERSONA_FISICA                        IS 'Subtipo de PER_PERSONA con los datos propios de un individuo (nacional o extranjero).';
COMMENT ON COLUMN PER_PERSONA_FISICA.ID_PERSONA_FISICA      IS 'Identificador de la persona fisica. Es el mismo valor de PER_PERSONA.ID_PERSONA (subtipo).';
COMMENT ON COLUMN PER_PERSONA_FISICA.TIPO_PERS              IS 'Discriminador heredado de PER_PERSONA. Solo admite N o E; impide que una empresa sea persona fisica.';
COMMENT ON COLUMN PER_PERSONA_FISICA.NOMBRE_PEFI            IS 'Nombre de pila.';
COMMENT ON COLUMN PER_PERSONA_FISICA.APELLIDO1_PEFI         IS 'Primer apellido.';
COMMENT ON COLUMN PER_PERSONA_FISICA.APELLIDO2_PEFI         IS 'Segundo apellido. Opcional porque los extranjeros pueden no tenerlo.';
COMMENT ON COLUMN PER_PERSONA_FISICA.SEXO_PEFI              IS 'Sexo: M=Masculino, F=Femenino, O=Otro.';
COMMENT ON COLUMN PER_PERSONA_FISICA.FECHA_NACIMIENTO_PEFI  IS 'Fecha de nacimiento.';
COMMENT ON COLUMN PER_PERSONA_FISICA.ESTADO_CIVIL_PEFI      IS 'Estado civil: S=Soltero, C=Casado, D=Divorciado, V=Viudo, U=Union libre.';
COMMENT ON COLUMN PER_PERSONA_FISICA.ESCOLARIDAD_PEFI       IS 'Escolaridad: N=Ninguna, P=Primaria, S=Secundaria, T=Tecnico, U=Universitaria, G=Posgrado.';
COMMENT ON COLUMN PER_PERSONA_FISICA.ID_PAIS_NACIONALIDAD   IS 'Pais de nacionalidad. FK a CAT_PAIS (rol: nacionalidad).';
COMMENT ON COLUMN PER_PERSONA_FISICA.ID_PAIS_RESIDENCIA     IS 'Pais de residencia. FK a CAT_PAIS (rol: residencia).';
COMMENT ON COLUMN PER_PERSONA_FISICA.PUESTO_PEFI            IS 'Puesto que desempena la persona en su trabajo.';
COMMENT ON COLUMN PER_PERSONA_FISICA.EMPRESA_LABORA_PEFI    IS 'Nombre de la empresa donde labora.';
COMMENT ON COLUMN PER_PERSONA_FISICA.ES_ASEGURADO_PEFI      IS 'Indica si la persona esta asegurada: S=Si, N=No.';
COMMENT ON COLUMN PER_PERSONA_FISICA.USUARIO_CREA_PEFI      IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PER_PERSONA_FISICA.FECHA_CREA_PEFI        IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PER_PERSONA_FISICA.USUARIO_MOD_PEFI       IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PER_PERSONA_FISICA.FECHA_MOD_PEFI         IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PER_PERSONA_JURIDICA
CREATE TABLE PER_PERSONA_JURIDICA (
    ID_PERSONA_JURIDICA      NUMBER(10)     NOT NULL,
    TIPO_PERS                VARCHAR2(1)    DEFAULT 'J' NOT NULL,
    RAZON_SOCIAL_PEJU        VARCHAR2(150)  NOT NULL,
    NOMBRE_COMERCIAL_PEJU    VARCHAR2(150),
    FECHA_CONSTITUCION_PEJU  DATE,
    ID_PAIS_ORIGEN           NUMBER(10)     NOT NULL,
    SITIO_WEB_PEJU           VARCHAR2(150),
    USUARIO_CREA_PEJU        VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_PEJU          TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PEJU         VARCHAR2(30),
    FECHA_MOD_PEJU           TIMESTAMP,
    CONSTRAINT PK_PEJU PRIMARY KEY (ID_PERSONA_JURIDICA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_PEJU_PERS FOREIGN KEY (ID_PERSONA_JURIDICA, TIPO_PERS)
        REFERENCES PER_PERSONA (ID_PERSONA, TIPO_PERS),
    CONSTRAINT FK_PEJU_PAIS_ORI FOREIGN KEY (ID_PAIS_ORIGEN)
        REFERENCES CAT_PAIS (ID_PAIS),
    CONSTRAINT CK_PEJU_TIPO CHECK (TIPO_PERS = 'J')
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PER_PERSONA_JURIDICA                          IS 'Subtipo de PER_PERSONA con los datos propios de una empresa.';
COMMENT ON COLUMN PER_PERSONA_JURIDICA.ID_PERSONA_JURIDICA      IS 'Identificador de la persona juridica. Es el mismo valor de PER_PERSONA.ID_PERSONA (subtipo).';
COMMENT ON COLUMN PER_PERSONA_JURIDICA.TIPO_PERS                IS 'Discriminador heredado de PER_PERSONA. Solo admite J; impide que un individuo sea persona juridica.';
COMMENT ON COLUMN PER_PERSONA_JURIDICA.RAZON_SOCIAL_PEJU        IS 'Razon social inscrita.';
COMMENT ON COLUMN PER_PERSONA_JURIDICA.NOMBRE_COMERCIAL_PEJU    IS 'Nombre comercial o de fantasia.';
COMMENT ON COLUMN PER_PERSONA_JURIDICA.FECHA_CONSTITUCION_PEJU  IS 'Fecha de constitucion de la sociedad.';
COMMENT ON COLUMN PER_PERSONA_JURIDICA.ID_PAIS_ORIGEN           IS 'Pais donde esta constituida la empresa. FK a CAT_PAIS (rol: origen).';
COMMENT ON COLUMN PER_PERSONA_JURIDICA.SITIO_WEB_PEJU           IS 'Direccion del sitio web.';
COMMENT ON COLUMN PER_PERSONA_JURIDICA.USUARIO_CREA_PEJU        IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PER_PERSONA_JURIDICA.FECHA_CREA_PEJU          IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PER_PERSONA_JURIDICA.USUARIO_MOD_PEJU         IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PER_PERSONA_JURIDICA.FECHA_MOD_PEJU           IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PER_DIRECCION
CREATE TABLE PER_DIRECCION (
    ID_DIRECCION         NUMBER(10)     DEFAULT SEQ_PER_DIRECCION.NEXTVAL NOT NULL,
    ID_PERSONA           NUMBER(10)     NOT NULL,
    TIPO_DIRE            VARCHAR2(1)    NOT NULL,
    ID_DISTRITO          NUMBER(10)     NOT NULL,
    SENNAS_EXACTAS_DIRE  VARCHAR2(250)  NOT NULL,
    ES_PRINCIPAL_DIRE    VARCHAR2(1)    DEFAULT 'N' NOT NULL,
    ESTADO_DIRE          VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_DIRE    VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_DIRE      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_DIRE     VARCHAR2(30),
    FECHA_MOD_DIRE       TIMESTAMP,
    CONSTRAINT PK_DIRE PRIMARY KEY (ID_DIRECCION)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_DIRE_PERS FOREIGN KEY (ID_PERSONA)
        REFERENCES PER_PERSONA (ID_PERSONA),
    CONSTRAINT FK_DIRE_DIST FOREIGN KEY (ID_DISTRITO)
        REFERENCES CAT_DISTRITO (ID_DISTRITO),
    CONSTRAINT UK_DIRE_PERS_TIPO UNIQUE (ID_PERSONA, TIPO_DIRE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_DIRE_TIPO CHECK (TIPO_DIRE IN ('C','T')),
    CONSTRAINT CK_DIRE_PRINCIPAL CHECK (ES_PRINCIPAL_DIRE IN ('S','N')),
    CONSTRAINT CK_DIRE_ESTADO CHECK (ESTADO_DIRE IN ('A','I'))
) TABLESPACE TBS_DATOS;

CREATE UNIQUE INDEX UX_DIRE_PRINCIPAL
    ON PER_DIRECCION (CASE WHEN ES_PRINCIPAL_DIRE = 'S' THEN ID_PERSONA END)
    TABLESPACE TBS_INDICES;

COMMENT ON TABLE  PER_DIRECCION                      IS 'Direcciones de una persona. Cada persona puede tener una direccion de casa y una de trabajo.';
COMMENT ON COLUMN PER_DIRECCION.ID_DIRECCION         IS 'Identificador unico de la direccion.';
COMMENT ON COLUMN PER_DIRECCION.ID_PERSONA           IS 'Persona duena de la direccion. FK a PER_PERSONA.';
COMMENT ON COLUMN PER_DIRECCION.TIPO_DIRE            IS 'Tipo de direccion: C=Casa, T=Trabajo.';
COMMENT ON COLUMN PER_DIRECCION.ID_DISTRITO          IS 'Distrito donde se ubica. FK a CAT_DISTRITO.';
COMMENT ON COLUMN PER_DIRECCION.SENNAS_EXACTAS_DIRE  IS 'Senas exactas de la direccion.';
COMMENT ON COLUMN PER_DIRECCION.ES_PRINCIPAL_DIRE    IS 'Indica si es la direccion principal de la persona: S=Si, N=No.';
COMMENT ON COLUMN PER_DIRECCION.ESTADO_DIRE          IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PER_DIRECCION.USUARIO_CREA_DIRE    IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PER_DIRECCION.FECHA_CREA_DIRE      IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PER_DIRECCION.USUARIO_MOD_DIRE     IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PER_DIRECCION.FECHA_MOD_DIRE       IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PER_CONTACTO
CREATE TABLE PER_CONTACTO (
    ID_CONTACTO        NUMBER(10)     DEFAULT SEQ_PER_CONTACTO.NEXTVAL NOT NULL,
    ID_PERSONA         NUMBER(10)     NOT NULL,
    TIPO_CONT          VARCHAR2(1)    NOT NULL,
    VALOR_CONT         VARCHAR2(100)  NOT NULL,
    ES_PRINCIPAL_CONT  VARCHAR2(1)    DEFAULT 'N' NOT NULL,
    ESTADO_CONT        VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_CONT  VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_CONT    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_CONT   VARCHAR2(30),
    FECHA_MOD_CONT     TIMESTAMP,
    CONSTRAINT PK_CONT PRIMARY KEY (ID_CONTACTO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_CONT_PERS FOREIGN KEY (ID_PERSONA)
        REFERENCES PER_PERSONA (ID_PERSONA),
    CONSTRAINT UK_CONT_PERS_TIPO_VAL UNIQUE (ID_PERSONA, TIPO_CONT, VALOR_CONT)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_CONT_TIPO CHECK (TIPO_CONT IN ('T','C','F','E')),
    CONSTRAINT CK_CONT_FORMATO CHECK (
            (TIPO_CONT = 'E' AND VALOR_CONT LIKE '_%@_%._%')
            OR (TIPO_CONT <> 'E' AND REGEXP_LIKE(VALOR_CONT, '^[0-9+ -]{8,20}$'))
        ),
    CONSTRAINT CK_CONT_PRINCIPAL CHECK (ES_PRINCIPAL_CONT IN ('S','N')),
    CONSTRAINT CK_CONT_ESTADO CHECK (ESTADO_CONT IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PER_CONTACTO                    IS 'Medios de contacto de una persona: telefono, celular, fax y correo electronico.';
COMMENT ON COLUMN PER_CONTACTO.ID_CONTACTO        IS 'Identificador unico del contacto.';
COMMENT ON COLUMN PER_CONTACTO.ID_PERSONA         IS 'Persona duena del contacto. FK a PER_PERSONA.';
COMMENT ON COLUMN PER_CONTACTO.TIPO_CONT          IS 'Tipo de contacto: T=Telefono, C=Celular, F=Fax, E=Email.';
COMMENT ON COLUMN PER_CONTACTO.VALOR_CONT         IS 'Numero o direccion de correo segun el tipo.';
COMMENT ON COLUMN PER_CONTACTO.ES_PRINCIPAL_CONT  IS 'Indica si es el contacto principal de su tipo: S=Si, N=No.';
COMMENT ON COLUMN PER_CONTACTO.ESTADO_CONT        IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PER_CONTACTO.USUARIO_CREA_CONT  IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PER_CONTACTO.FECHA_CREA_CONT    IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PER_CONTACTO.USUARIO_MOD_CONT   IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PER_CONTACTO.FECHA_MOD_CONT     IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PER_CLIENTE
CREATE TABLE PER_CLIENTE (
    ID_CLIENTE             NUMBER(10)    DEFAULT SEQ_PER_CLIENTE.NEXTVAL NOT NULL,
    ID_PERSONA             NUMBER(10)    NOT NULL,
    CODIGO_CLI             VARCHAR2(20)  NOT NULL,
    FECHA_INGRESO_CLI      DATE          DEFAULT SYSDATE NOT NULL,
    ES_PREFERENCIAL_CLI    VARCHAR2(1)   DEFAULT 'N' NOT NULL,
    MONTO_MAX_CREDITO_CLI  NUMBER(14,2)  DEFAULT 0 NOT NULL,
    DIAS_CREDITO_CLI       NUMBER(4)     DEFAULT 0 NOT NULL,
    ES_DEFECTO_CLI         VARCHAR2(1)   DEFAULT 'N' NOT NULL,
    ESTADO_CLI             VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_CLI       VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_CLI         TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_CLI        VARCHAR2(30),
    FECHA_MOD_CLI          TIMESTAMP,
    CONSTRAINT PK_CLI PRIMARY KEY (ID_CLIENTE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_CLI_PERS FOREIGN KEY (ID_PERSONA)
        REFERENCES PER_PERSONA (ID_PERSONA),
    CONSTRAINT UK_CLI_PERSONA UNIQUE (ID_PERSONA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT UK_CLI_CODIGO UNIQUE (CODIGO_CLI)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_CLI_MONTO_CREDITO CHECK (MONTO_MAX_CREDITO_CLI >= 0),
    CONSTRAINT CK_CLI_DIAS_CREDITO CHECK (DIAS_CREDITO_CLI >= 0),
    CONSTRAINT CK_CLI_CRED_PREF CHECK (ES_PREFERENCIAL_CLI = 'S' OR MONTO_MAX_CREDITO_CLI = 0),
    CONSTRAINT CK_CLI_PREFERENCIAL CHECK (ES_PREFERENCIAL_CLI IN ('S','N')),
    CONSTRAINT CK_CLI_DEFECTO CHECK (ES_DEFECTO_CLI IN ('S','N')),
    CONSTRAINT CK_CLI_ESTADO CHECK (ESTADO_CLI IN ('A','I'))
) TABLESPACE TBS_DATOS;

CREATE UNIQUE INDEX UX_CLI_DEFECTO
    ON PER_CLIENTE (CASE WHEN ES_DEFECTO_CLI = 'S' THEN 1 END)
    TABLESPACE TBS_INDICES;

COMMENT ON TABLE  PER_CLIENTE                        IS 'Rol de cliente de una persona fisica o juridica. Incluye el cliente por defecto usado en ventas de contado sin cliente registrado.';
COMMENT ON COLUMN PER_CLIENTE.ID_CLIENTE             IS 'Identificador unico del cliente.';
COMMENT ON COLUMN PER_CLIENTE.ID_PERSONA             IS 'Persona (fisica o juridica) que es cliente. FK a PER_PERSONA.';
COMMENT ON COLUMN PER_CLIENTE.CODIGO_CLI             IS 'Codigo interno del cliente.';
COMMENT ON COLUMN PER_CLIENTE.FECHA_INGRESO_CLI      IS 'Fecha de ingreso a la empresa como cliente.';
COMMENT ON COLUMN PER_CLIENTE.ES_PREFERENCIAL_CLI    IS 'Indica si es cliente preferencial (puede comprar a credito): S=Si, N=No.';
COMMENT ON COLUMN PER_CLIENTE.MONTO_MAX_CREDITO_CLI  IS 'Monto maximo de credito permitido. Solo puede ser mayor a cero en clientes preferenciales.';
COMMENT ON COLUMN PER_CLIENTE.DIAS_CREDITO_CLI       IS 'Plazo de credito en dias.';
COMMENT ON COLUMN PER_CLIENTE.ES_DEFECTO_CLI         IS 'Indica si es el cliente por defecto de la facturacion: S=Si, N=No. Solo puede existir uno.';
COMMENT ON COLUMN PER_CLIENTE.ESTADO_CLI             IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PER_CLIENTE.USUARIO_CREA_CLI       IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PER_CLIENTE.FECHA_CREA_CLI         IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PER_CLIENTE.USUARIO_MOD_CLI        IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PER_CLIENTE.FECHA_MOD_CLI          IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PER_PROVEEDOR
CREATE TABLE PER_PROVEEDOR (
    ID_PROVEEDOR           NUMBER(10)     DEFAULT SEQ_PER_PROVEEDOR.NEXTVAL NOT NULL,
    ID_PERSONA_JURIDICA    NUMBER(10)     NOT NULL,
    CODIGO_PROVE           VARCHAR2(20)   NOT NULL,
    FECHA_INGRESO_PROVE    DATE           DEFAULT SYSDATE NOT NULL,
    LIMITE_CREDITO_PROVE   NUMBER(14,2)   DEFAULT 0 NOT NULL,
    DIAS_CREDITO_PROVE     NUMBER(4)      DEFAULT 0 NOT NULL,
    NOMBRE_CONTACTO_PROVE  VARCHAR2(100),
    ESTADO_PROVE           VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_PROVE     VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_PROVE       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PROVE      VARCHAR2(30),
    FECHA_MOD_PROVE        TIMESTAMP,
    CONSTRAINT PK_PROVE PRIMARY KEY (ID_PROVEEDOR)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_PROVE_PEJU FOREIGN KEY (ID_PERSONA_JURIDICA)
        REFERENCES PER_PERSONA_JURIDICA (ID_PERSONA_JURIDICA),
    CONSTRAINT UK_PROVE_PEJU UNIQUE (ID_PERSONA_JURIDICA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT UK_PROVE_CODIGO UNIQUE (CODIGO_PROVE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_PROVE_LIMITE CHECK (LIMITE_CREDITO_PROVE >= 0),
    CONSTRAINT CK_PROVE_DIAS_CREDITO CHECK (DIAS_CREDITO_PROVE >= 0),
    CONSTRAINT CK_PROVE_ESTADO CHECK (ESTADO_PROVE IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PER_PROVEEDOR                        IS 'Rol de proveedor. Solo una persona juridica (empresa) puede ser proveedor.';
COMMENT ON COLUMN PER_PROVEEDOR.ID_PROVEEDOR           IS 'Identificador unico del proveedor.';
COMMENT ON COLUMN PER_PROVEEDOR.ID_PERSONA_JURIDICA    IS 'Empresa que es proveedor. FK a PER_PERSONA_JURIDICA, lo que impide registrar individuos como proveedores.';
COMMENT ON COLUMN PER_PROVEEDOR.CODIGO_PROVE           IS 'Codigo interno del proveedor.';
COMMENT ON COLUMN PER_PROVEEDOR.FECHA_INGRESO_PROVE    IS 'Fecha de inicio de la relacion comercial.';
COMMENT ON COLUMN PER_PROVEEDOR.LIMITE_CREDITO_PROVE   IS 'Limite de credito que el proveedor le otorga al negocio.';
COMMENT ON COLUMN PER_PROVEEDOR.DIAS_CREDITO_PROVE     IS 'Plazo de credito en dias otorgado por el proveedor.';
COMMENT ON COLUMN PER_PROVEEDOR.NOMBRE_CONTACTO_PROVE  IS 'Nombre del agente o persona de contacto en el proveedor.';
COMMENT ON COLUMN PER_PROVEEDOR.ESTADO_PROVE           IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PER_PROVEEDOR.USUARIO_CREA_PROVE     IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PER_PROVEEDOR.FECHA_CREA_PROVE       IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PER_PROVEEDOR.USUARIO_MOD_PROVE      IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PER_PROVEEDOR.FECHA_MOD_PROVE        IS 'Fecha y hora de la ultima modificacion.';

PROMPT Modulo PER_ creado: 7 tablas, 7 secuencias.


--------------------------------------------------------------------------------
-- SECCION 4 de 12: modulo SEG_
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Configuracion del negocio, sucursales y usuarios
--------------------------------------------------------------------------------
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SECUENCIAS DEL MODULO
CREATE SEQUENCE SEQ_SEG_EMPRESA          START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_SEG_SUCURSAL         START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_SEG_USUARIO          START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_SEG_USUARIO_SUCURSAL  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- TABLA: SEG_EMPRESA
CREATE TABLE SEG_EMPRESA (
    ID_EMPRESA           NUMBER(10)     DEFAULT SEQ_SEG_EMPRESA.NEXTVAL NOT NULL,
    ID_PERSONA_JURIDICA  NUMBER(10)     NOT NULL,
    TIPO_NEGOCIO_EMP     VARCHAR2(15)   NOT NULL,
    NOMBRE_SISTEMA_EMP   VARCHAR2(100)  NOT NULL,
    MONEDA_BASE_EMP      VARCHAR2(3)    DEFAULT 'CRC' NOT NULL,
    FECHA_INICIO_OP_EMP  DATE           DEFAULT SYSDATE NOT NULL,
    ESTADO_EMP           VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_EMP     VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_EMP       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_EMP      VARCHAR2(30),
    FECHA_MOD_EMP        TIMESTAMP,
    CONSTRAINT PK_EMP PRIMARY KEY (ID_EMPRESA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_EMP_PEJU FOREIGN KEY (ID_PERSONA_JURIDICA)
        REFERENCES PER_PERSONA_JURIDICA (ID_PERSONA_JURIDICA),
    CONSTRAINT CK_EMP_TIPO_NEGOCIO CHECK (TIPO_NEGOCIO_EMP IN ('SUPERMERCADO','FERRETERIA','SUMINISTROS')),
    CONSTRAINT CK_EMP_ESTADO CHECK (ESTADO_EMP IN ('A','I'))
) TABLESPACE TBS_DATOS;

CREATE UNIQUE INDEX UX_EMP_ACTIVA
    ON SEG_EMPRESA (CASE WHEN ESTADO_EMP = 'A' THEN 1 END)
    TABLESPACE TBS_INDICES;

COMMENT ON TABLE  SEG_EMPRESA                      IS 'Configuracion del negocio que opera la instancia. Los negocios son mutuamente excluyentes: solo una configuracion puede estar activa.';
COMMENT ON COLUMN SEG_EMPRESA.ID_EMPRESA           IS 'Identificador unico de la configuracion de empresa.';
COMMENT ON COLUMN SEG_EMPRESA.ID_PERSONA_JURIDICA  IS 'Persona juridica duena del negocio. FK a PER_PERSONA_JURIDICA.';
COMMENT ON COLUMN SEG_EMPRESA.TIPO_NEGOCIO_EMP     IS 'Tipo de negocio configurado: SUPERMERCADO, FERRETERIA o SUMINISTROS.';
COMMENT ON COLUMN SEG_EMPRESA.NOMBRE_SISTEMA_EMP   IS 'Nombre con que se identifica el punto de venta.';
COMMENT ON COLUMN SEG_EMPRESA.MONEDA_BASE_EMP      IS 'Codigo ISO 4217 de la moneda base.';
COMMENT ON COLUMN SEG_EMPRESA.FECHA_INICIO_OP_EMP  IS 'Fecha desde la que rige la configuracion.';
COMMENT ON COLUMN SEG_EMPRESA.ESTADO_EMP           IS 'Estado del registro: A=Activa (vigente), I=Inactiva (historica).';
COMMENT ON COLUMN SEG_EMPRESA.USUARIO_CREA_EMP     IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN SEG_EMPRESA.FECHA_CREA_EMP       IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN SEG_EMPRESA.USUARIO_MOD_EMP      IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN SEG_EMPRESA.FECHA_MOD_EMP        IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: SEG_SUCURSAL
CREATE TABLE SEG_SUCURSAL (
    ID_SUCURSAL         NUMBER(10)     DEFAULT SEQ_SEG_SUCURSAL.NEXTVAL NOT NULL,
    ID_EMPRESA          NUMBER(10)     NOT NULL,
    ID_DISTRITO         NUMBER(10)     NOT NULL,
    CODIGO_SUC          VARCHAR2(20)   NOT NULL,
    NOMBRE_SUC          VARCHAR2(100)  NOT NULL,
    SENNAS_EXACTAS_SUC  VARCHAR2(250),
    TELEFONO_SUC        VARCHAR2(25),
    ES_CASA_MATRIZ_SUC  VARCHAR2(1)    DEFAULT 'N' NOT NULL,
    FECHA_APERTURA_SUC  DATE           DEFAULT SYSDATE NOT NULL,
    ESTADO_SUC          VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_SUC    VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_SUC      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_SUC     VARCHAR2(30),
    FECHA_MOD_SUC       TIMESTAMP,
    CONSTRAINT PK_SUC PRIMARY KEY (ID_SUCURSAL)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_SUC_EMP FOREIGN KEY (ID_EMPRESA)
        REFERENCES SEG_EMPRESA (ID_EMPRESA),
    CONSTRAINT FK_SUC_DIST FOREIGN KEY (ID_DISTRITO)
        REFERENCES CAT_DISTRITO (ID_DISTRITO),
    CONSTRAINT UK_SUC_CODIGO UNIQUE (CODIGO_SUC)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_SUC_CASA_MATRIZ CHECK (ES_CASA_MATRIZ_SUC IN ('S','N')),
    CONSTRAINT CK_SUC_ESTADO CHECK (ESTADO_SUC IN ('A','I'))
) TABLESPACE TBS_DATOS;

CREATE UNIQUE INDEX UX_SUC_CASA_MATRIZ
    ON SEG_SUCURSAL (CASE WHEN ES_CASA_MATRIZ_SUC = 'S' THEN 1 END)
    TABLESPACE TBS_INDICES;

COMMENT ON TABLE  SEG_SUCURSAL                     IS 'Sucursales (negocios) de la cadena. Permite que el sistema sea multisucursal.';
COMMENT ON COLUMN SEG_SUCURSAL.ID_SUCURSAL         IS 'Identificador unico de la sucursal.';
COMMENT ON COLUMN SEG_SUCURSAL.ID_EMPRESA          IS 'Configuracion de empresa a la que pertenece. FK a SEG_EMPRESA.';
COMMENT ON COLUMN SEG_SUCURSAL.ID_DISTRITO         IS 'Distrito donde se ubica. FK a CAT_DISTRITO.';
COMMENT ON COLUMN SEG_SUCURSAL.CODIGO_SUC          IS 'Codigo interno de la sucursal.';
COMMENT ON COLUMN SEG_SUCURSAL.NOMBRE_SUC          IS 'Nombre de la sucursal.';
COMMENT ON COLUMN SEG_SUCURSAL.SENNAS_EXACTAS_SUC  IS 'Senas exactas del local.';
COMMENT ON COLUMN SEG_SUCURSAL.TELEFONO_SUC        IS 'Telefono del local.';
COMMENT ON COLUMN SEG_SUCURSAL.ES_CASA_MATRIZ_SUC  IS 'Indica si es la casa matriz: S=Si, N=No. Solo puede existir una.';
COMMENT ON COLUMN SEG_SUCURSAL.FECHA_APERTURA_SUC  IS 'Fecha de apertura.';
COMMENT ON COLUMN SEG_SUCURSAL.ESTADO_SUC          IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN SEG_SUCURSAL.USUARIO_CREA_SUC    IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN SEG_SUCURSAL.FECHA_CREA_SUC      IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN SEG_SUCURSAL.USUARIO_MOD_SUC     IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN SEG_SUCURSAL.FECHA_MOD_SUC       IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: SEG_USUARIO
CREATE TABLE SEG_USUARIO (
    ID_USUARIO              NUMBER(10)     DEFAULT SEQ_SEG_USUARIO.NEXTVAL NOT NULL,
    ID_PERSONA_FISICA       NUMBER(10)     NOT NULL,
    NOMBRE_USUARIO_USU      VARCHAR2(30)   NOT NULL,
    CLAVE_HASH_USU          VARCHAR2(256)  NOT NULL,
    ROL_USU                 VARCHAR2(10)   NOT NULL,
    FECHA_ALTA_USU          DATE           DEFAULT SYSDATE NOT NULL,
    FECHA_ULT_ACCESO_USU    TIMESTAMP,
    INTENTOS_FALLIDOS_USU   NUMBER(2)      DEFAULT 0 NOT NULL,
    DEBE_CAMBIAR_CLAVE_USU  VARCHAR2(1)    DEFAULT 'S' NOT NULL,
    ESTADO_USU              VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_USU        VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_USU          TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_USU         VARCHAR2(30),
    FECHA_MOD_USU           TIMESTAMP,
    CONSTRAINT PK_USU PRIMARY KEY (ID_USUARIO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_USU_PEFI FOREIGN KEY (ID_PERSONA_FISICA)
        REFERENCES PER_PERSONA_FISICA (ID_PERSONA_FISICA),
    CONSTRAINT UK_USU_NOMBRE UNIQUE (NOMBRE_USUARIO_USU)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT UK_USU_PEFI UNIQUE (ID_PERSONA_FISICA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_USU_ROL CHECK (ROL_USU IN ('ADMIN','SUPERVISOR','CAJERO','BODEGUERO','CONTADOR')),
    CONSTRAINT CK_USU_INTENTOS CHECK (INTENTOS_FALLIDOS_USU >= 0),
    CONSTRAINT CK_USU_DEBE_CAMBIAR_CLAVE CHECK (DEBE_CAMBIAR_CLAVE_USU IN ('S','N')),
    CONSTRAINT CK_USU_ESTADO CHECK (ESTADO_USU IN ('A','I','B'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  SEG_USUARIO                         IS 'Usuarios del sistema. Permite que el sistema sea multiusuario. Todo usuario es una persona fisica.';
COMMENT ON COLUMN SEG_USUARIO.ID_USUARIO              IS 'Identificador unico del usuario.';
COMMENT ON COLUMN SEG_USUARIO.ID_PERSONA_FISICA       IS 'Persona fisica que es usuario. FK a PER_PERSONA_FISICA.';
COMMENT ON COLUMN SEG_USUARIO.NOMBRE_USUARIO_USU      IS 'Nombre de inicio de sesion.';
COMMENT ON COLUMN SEG_USUARIO.CLAVE_HASH_USU          IS 'Hash de la contrasena. Nunca se guarda la contrasena en texto plano.';
COMMENT ON COLUMN SEG_USUARIO.ROL_USU                 IS 'Rol del usuario: ADMIN, SUPERVISOR, CAJERO, BODEGUERO o CONTADOR.';
COMMENT ON COLUMN SEG_USUARIO.FECHA_ALTA_USU          IS 'Fecha de creacion del usuario.';
COMMENT ON COLUMN SEG_USUARIO.FECHA_ULT_ACCESO_USU    IS 'Fecha y hora del ultimo inicio de sesion.';
COMMENT ON COLUMN SEG_USUARIO.INTENTOS_FALLIDOS_USU   IS 'Intentos de acceso fallidos consecutivos.';
COMMENT ON COLUMN SEG_USUARIO.DEBE_CAMBIAR_CLAVE_USU  IS 'Indica si debe cambiar la contrasena en el proximo ingreso: S=Si, N=No.';
COMMENT ON COLUMN SEG_USUARIO.ESTADO_USU              IS 'Estado del registro: A=Activo, I=Inactivo, B=Bloqueado.';
COMMENT ON COLUMN SEG_USUARIO.USUARIO_CREA_USU        IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN SEG_USUARIO.FECHA_CREA_USU          IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN SEG_USUARIO.USUARIO_MOD_USU         IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN SEG_USUARIO.FECHA_MOD_USU           IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: SEG_USUARIO_SUCURSAL
CREATE TABLE SEG_USUARIO_SUCURSAL (
    ID_USUARIO_SUCURSAL  NUMBER(10)    DEFAULT SEQ_SEG_USUARIO_SUCURSAL.NEXTVAL NOT NULL,
    ID_USUARIO           NUMBER(10)    NOT NULL,
    ID_SUCURSAL          NUMBER(10)    NOT NULL,
    ES_DEFECTO_USSU      VARCHAR2(1)   DEFAULT 'N' NOT NULL,
    FECHA_ASIGNA_USSU    DATE          DEFAULT SYSDATE NOT NULL,
    ESTADO_USSU          VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_USSU    VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_USSU      TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_USSU     VARCHAR2(30),
    FECHA_MOD_USSU       TIMESTAMP,
    CONSTRAINT PK_USSU PRIMARY KEY (ID_USUARIO_SUCURSAL)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_USSU_USU FOREIGN KEY (ID_USUARIO)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT FK_USSU_SUC FOREIGN KEY (ID_SUCURSAL)
        REFERENCES SEG_SUCURSAL (ID_SUCURSAL),
    CONSTRAINT UK_USSU_USU_SUC UNIQUE (ID_USUARIO, ID_SUCURSAL)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_USSU_DEFECTO CHECK (ES_DEFECTO_USSU IN ('S','N')),
    CONSTRAINT CK_USSU_ESTADO CHECK (ESTADO_USSU IN ('A','I'))
) TABLESPACE TBS_DATOS;

CREATE UNIQUE INDEX UX_USSU_DEFECTO
    ON SEG_USUARIO_SUCURSAL (CASE WHEN ES_DEFECTO_USSU = 'S' THEN ID_USUARIO END)
    TABLESPACE TBS_INDICES;

COMMENT ON TABLE  SEG_USUARIO_SUCURSAL                      IS 'Sucursales en las que un usuario esta autorizado a trabajar.';
COMMENT ON COLUMN SEG_USUARIO_SUCURSAL.ID_USUARIO_SUCURSAL  IS 'Identificador unico de la asignacion.';
COMMENT ON COLUMN SEG_USUARIO_SUCURSAL.ID_USUARIO           IS 'Usuario asignado. FK a SEG_USUARIO.';
COMMENT ON COLUMN SEG_USUARIO_SUCURSAL.ID_SUCURSAL          IS 'Sucursal asignada. FK a SEG_SUCURSAL.';
COMMENT ON COLUMN SEG_USUARIO_SUCURSAL.ES_DEFECTO_USSU      IS 'Indica si es la sucursal por defecto del usuario: S=Si, N=No. Solo una por usuario.';
COMMENT ON COLUMN SEG_USUARIO_SUCURSAL.FECHA_ASIGNA_USSU    IS 'Fecha de la asignacion.';
COMMENT ON COLUMN SEG_USUARIO_SUCURSAL.ESTADO_USSU          IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN SEG_USUARIO_SUCURSAL.USUARIO_CREA_USSU    IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN SEG_USUARIO_SUCURSAL.FECHA_CREA_USSU      IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN SEG_USUARIO_SUCURSAL.USUARIO_MOD_USSU     IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN SEG_USUARIO_SUCURSAL.FECHA_MOD_USSU       IS 'Fecha y hora de la ultima modificacion.';

PROMPT Modulo SEG_ creado: 4 tablas, 4 secuencias.


--------------------------------------------------------------------------------
-- SECCION 5 de 12: modulo PRO_
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Productos, servicios, precios y lotes
--------------------------------------------------------------------------------
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SECUENCIAS DEL MODULO
CREATE SEQUENCE SEQ_PRO_FAMILIA_PRODUCTO  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRO_IMPUESTO          START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRO_PRODUCTO          START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRO_CODIGO_BARRA      START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRO_PRODUCTO_SUCURSAL  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRO_PRECIO_HIST       START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRO_LOTE              START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRO_SERVICIO          START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- TABLA: PRO_FAMILIA_PRODUCTO
CREATE TABLE PRO_FAMILIA_PRODUCTO (
    ID_FAMILIA_PRODUCTO        NUMBER(10)     DEFAULT SEQ_PRO_FAMILIA_PRODUCTO.NEXTVAL NOT NULL,
    ID_FAMILIA_PRODUCTO_PADRE  NUMBER(10),
    CODIGO_FAMI                VARCHAR2(20)   NOT NULL,
    NOMBRE_FAMI                VARCHAR2(50)   NOT NULL,
    DESCRIPCION_FAMI           VARCHAR2(200),
    ESTADO_FAMI                VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_FAMI          VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_FAMI            TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_FAMI           VARCHAR2(30),
    FECHA_MOD_FAMI             TIMESTAMP,
    CONSTRAINT PK_FAMI PRIMARY KEY (ID_FAMILIA_PRODUCTO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_FAMI_FAMI_PADRE FOREIGN KEY (ID_FAMILIA_PRODUCTO_PADRE)
        REFERENCES PRO_FAMILIA_PRODUCTO (ID_FAMILIA_PRODUCTO),
    CONSTRAINT UK_FAMI_CODIGO UNIQUE (CODIGO_FAMI)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_FAMI_PADRE CHECK (ID_FAMILIA_PRODUCTO_PADRE <> ID_FAMILIA_PRODUCTO),
    CONSTRAINT CK_FAMI_ESTADO CHECK (ESTADO_FAMI IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRO_FAMILIA_PRODUCTO                            IS 'Familias de productos (bebidas, carnes, verduras, etc.). Admite subfamilias.';
COMMENT ON COLUMN PRO_FAMILIA_PRODUCTO.ID_FAMILIA_PRODUCTO        IS 'Identificador unico de la familia.';
COMMENT ON COLUMN PRO_FAMILIA_PRODUCTO.ID_FAMILIA_PRODUCTO_PADRE  IS 'Familia de nivel superior. FK a PRO_FAMILIA_PRODUCTO (rol: padre). Nulo en familias raiz.';
COMMENT ON COLUMN PRO_FAMILIA_PRODUCTO.CODIGO_FAMI                IS 'Codigo interno de la familia.';
COMMENT ON COLUMN PRO_FAMILIA_PRODUCTO.NOMBRE_FAMI                IS 'Nombre de la familia.';
COMMENT ON COLUMN PRO_FAMILIA_PRODUCTO.DESCRIPCION_FAMI           IS 'Descripcion de la familia.';
COMMENT ON COLUMN PRO_FAMILIA_PRODUCTO.ESTADO_FAMI                IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PRO_FAMILIA_PRODUCTO.USUARIO_CREA_FAMI          IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRO_FAMILIA_PRODUCTO.FECHA_CREA_FAMI            IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRO_FAMILIA_PRODUCTO.USUARIO_MOD_FAMI           IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRO_FAMILIA_PRODUCTO.FECHA_MOD_FAMI             IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PRO_IMPUESTO
CREATE TABLE PRO_IMPUESTO (
    ID_IMPUESTO        NUMBER(10)    DEFAULT SEQ_PRO_IMPUESTO.NEXTVAL NOT NULL,
    CODIGO_IMPU        VARCHAR2(20)  NOT NULL,
    NOMBRE_IMPU        VARCHAR2(50)  NOT NULL,
    PORCENTAJE_IMPU    NUMBER(5,2)   NOT NULL,
    ESTADO_IMPU        VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_IMPU  VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_IMPU    TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_IMPU   VARCHAR2(30),
    FECHA_MOD_IMPU     TIMESTAMP,
    CONSTRAINT PK_IMPU PRIMARY KEY (ID_IMPUESTO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT UK_IMPU_CODIGO UNIQUE (CODIGO_IMPU)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_IMPU_PORCENTAJE CHECK (PORCENTAJE_IMPU > 0 AND PORCENTAJE_IMPU <= 100),
    CONSTRAINT CK_IMPU_ESTADO CHECK (ESTADO_IMPU IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRO_IMPUESTO                    IS 'Impuestos aplicables a productos y servicios gravados. Un producto o servicio sin impuesto asociado es exento.';
COMMENT ON COLUMN PRO_IMPUESTO.ID_IMPUESTO        IS 'Identificador unico del impuesto.';
COMMENT ON COLUMN PRO_IMPUESTO.CODIGO_IMPU        IS 'Codigo interno del impuesto.';
COMMENT ON COLUMN PRO_IMPUESTO.NOMBRE_IMPU        IS 'Nombre del impuesto.';
COMMENT ON COLUMN PRO_IMPUESTO.PORCENTAJE_IMPU    IS 'Porcentaje del impuesto. Siempre mayor a cero: la exencion se representa sin impuesto asociado.';
COMMENT ON COLUMN PRO_IMPUESTO.ESTADO_IMPU        IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PRO_IMPUESTO.USUARIO_CREA_IMPU  IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRO_IMPUESTO.FECHA_CREA_IMPU    IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRO_IMPUESTO.USUARIO_MOD_IMPU   IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRO_IMPUESTO.FECHA_MOD_IMPU     IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PRO_PRODUCTO
CREATE TABLE PRO_PRODUCTO (
    ID_PRODUCTO          NUMBER(10)     DEFAULT SEQ_PRO_PRODUCTO.NEXTVAL NOT NULL,
    ID_FAMILIA_PRODUCTO  NUMBER(10)     NOT NULL,
    ID_PROVEEDOR         NUMBER(10)     NOT NULL,
    ID_IMPUESTO          NUMBER(10),
    CODIGO_PROD          VARCHAR2(20)   NOT NULL,
    NOMBRE_PROD          VARCHAR2(150)  NOT NULL,
    DESCRIPCION_PROD     VARCHAR2(250),
    UNIDAD_MEDIDA_PROD   VARCHAR2(3)    DEFAULT 'UND' NOT NULL,
    PRECIO_COSTO_PROD    NUMBER(14,4)   DEFAULT 0 NOT NULL,
    ES_EXENTO_PROD       VARCHAR2(1)    GENERATED ALWAYS AS (CASE WHEN ID_IMPUESTO IS NULL THEN 'S' ELSE 'N' END) VIRTUAL,
    MANEJA_LOTE_PROD     VARCHAR2(1)    DEFAULT 'N' NOT NULL,
    STOCK_MINIMO_PROD    NUMBER(14,3)   DEFAULT 0 NOT NULL,
    ESTADO_PROD          VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_PROD    VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_PROD      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PROD     VARCHAR2(30),
    FECHA_MOD_PROD       TIMESTAMP,
    CONSTRAINT PK_PROD PRIMARY KEY (ID_PRODUCTO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_PROD_FAMI FOREIGN KEY (ID_FAMILIA_PRODUCTO)
        REFERENCES PRO_FAMILIA_PRODUCTO (ID_FAMILIA_PRODUCTO),
    CONSTRAINT FK_PROD_PROVE FOREIGN KEY (ID_PROVEEDOR)
        REFERENCES PER_PROVEEDOR (ID_PROVEEDOR),
    CONSTRAINT FK_PROD_IMPU FOREIGN KEY (ID_IMPUESTO)
        REFERENCES PRO_IMPUESTO (ID_IMPUESTO),
    CONSTRAINT UK_PROD_CODIGO UNIQUE (CODIGO_PROD)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_PROD_UNIDAD CHECK (UNIDAD_MEDIDA_PROD IN ('UND','KG','LT','CJ','PQ')),
    CONSTRAINT CK_PROD_COSTO CHECK (PRECIO_COSTO_PROD >= 0),
    CONSTRAINT CK_PROD_STOCK_MIN CHECK (STOCK_MINIMO_PROD >= 0),
    CONSTRAINT CK_PROD_MANEJA_LOTE CHECK (MANEJA_LOTE_PROD IN ('S','N')),
    CONSTRAINT CK_PROD_ESTADO CHECK (ESTADO_PROD IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRO_PRODUCTO                      IS 'Productos del inventario. El precio de venta no se almacena: se calcula en V_PRECIO_VENTA a partir de costo, utilidad, descuento e impuesto.';
COMMENT ON COLUMN PRO_PRODUCTO.ID_PRODUCTO          IS 'Identificador unico del producto.';
COMMENT ON COLUMN PRO_PRODUCTO.ID_FAMILIA_PRODUCTO  IS 'Familia a la que pertenece. FK a PRO_FAMILIA_PRODUCTO.';
COMMENT ON COLUMN PRO_PRODUCTO.ID_PROVEEDOR         IS 'Proveedor del producto. FK a PER_PROVEEDOR.';
COMMENT ON COLUMN PRO_PRODUCTO.ID_IMPUESTO          IS 'Impuesto que grava el producto. FK a PRO_IMPUESTO. Nulo significa producto exento.';
COMMENT ON COLUMN PRO_PRODUCTO.CODIGO_PROD          IS 'Codigo interno del producto.';
COMMENT ON COLUMN PRO_PRODUCTO.NOMBRE_PROD          IS 'Nombre del producto.';
COMMENT ON COLUMN PRO_PRODUCTO.DESCRIPCION_PROD     IS 'Descripcion ampliada.';
COMMENT ON COLUMN PRO_PRODUCTO.UNIDAD_MEDIDA_PROD   IS 'Unidad de medida: UND=Unidad, KG=Kilogramo, LT=Litro, CJ=Caja, PQ=Paquete.';
COMMENT ON COLUMN PRO_PRODUCTO.PRECIO_COSTO_PROD    IS 'Precio de costo vigente. Los costos anteriores quedan en PRO_PRECIO_HIST.';
COMMENT ON COLUMN PRO_PRODUCTO.ES_EXENTO_PROD       IS 'Columna virtual: S si el producto es exento de impuestos (sin impuesto asociado), N si es gravado.';
COMMENT ON COLUMN PRO_PRODUCTO.MANEJA_LOTE_PROD     IS 'Indica si el producto se controla por lote y fecha de vencimiento: S=Si, N=No.';
COMMENT ON COLUMN PRO_PRODUCTO.STOCK_MINIMO_PROD    IS 'Existencia minima antes de reordenar.';
COMMENT ON COLUMN PRO_PRODUCTO.ESTADO_PROD          IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PRO_PRODUCTO.USUARIO_CREA_PROD    IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRO_PRODUCTO.FECHA_CREA_PROD      IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRO_PRODUCTO.USUARIO_MOD_PROD     IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRO_PRODUCTO.FECHA_MOD_PROD       IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PRO_CODIGO_BARRA
CREATE TABLE PRO_CODIGO_BARRA (
    ID_CODIGO_BARRA    NUMBER(10)    DEFAULT SEQ_PRO_CODIGO_BARRA.NEXTVAL NOT NULL,
    ID_PRODUCTO        NUMBER(10)    NOT NULL,
    CODIGO_COBA        VARCHAR2(50)  NOT NULL,
    TIPO_COBA          VARCHAR2(20)  DEFAULT 'EAN13' NOT NULL,
    ES_PRINCIPAL_COBA  VARCHAR2(1)   DEFAULT 'N' NOT NULL,
    ESTADO_COBA        VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_COBA  VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_COBA    TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_COBA   VARCHAR2(30),
    FECHA_MOD_COBA     TIMESTAMP,
    CONSTRAINT PK_COBA PRIMARY KEY (ID_CODIGO_BARRA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_COBA_PROD FOREIGN KEY (ID_PRODUCTO)
        REFERENCES PRO_PRODUCTO (ID_PRODUCTO),
    CONSTRAINT UK_COBA_CODIGO UNIQUE (CODIGO_COBA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_COBA_TIPO CHECK (TIPO_COBA IN ('EAN13','EAN8','UPCA','ITF14','GS1128','INTERNO')),
    CONSTRAINT CK_COBA_PRINCIPAL CHECK (ES_PRINCIPAL_COBA IN ('S','N')),
    CONSTRAINT CK_COBA_ESTADO CHECK (ESTADO_COBA IN ('A','I'))
) TABLESPACE TBS_DATOS;

CREATE UNIQUE INDEX UX_COBA_PRINCIPAL
    ON PRO_CODIGO_BARRA (CASE WHEN ES_PRINCIPAL_COBA = 'S' THEN ID_PRODUCTO END)
    TABLESPACE TBS_INDICES;

COMMENT ON TABLE  PRO_CODIGO_BARRA                    IS 'Codigos de barras de un producto. Un mismo producto puede tener varios.';
COMMENT ON COLUMN PRO_CODIGO_BARRA.ID_CODIGO_BARRA    IS 'Identificador unico del codigo de barras.';
COMMENT ON COLUMN PRO_CODIGO_BARRA.ID_PRODUCTO        IS 'Producto al que pertenece. FK a PRO_PRODUCTO.';
COMMENT ON COLUMN PRO_CODIGO_BARRA.CODIGO_COBA        IS 'Codigo de barras. Unico en todo el sistema.';
COMMENT ON COLUMN PRO_CODIGO_BARRA.TIPO_COBA          IS 'Simbologia: EAN13, EAN8, UPCA, ITF14, GS1128 o INTERNO.';
COMMENT ON COLUMN PRO_CODIGO_BARRA.ES_PRINCIPAL_COBA  IS 'Indica si es el codigo principal del producto: S=Si, N=No. Solo uno por producto.';
COMMENT ON COLUMN PRO_CODIGO_BARRA.ESTADO_COBA        IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PRO_CODIGO_BARRA.USUARIO_CREA_COBA  IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRO_CODIGO_BARRA.FECHA_CREA_COBA    IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRO_CODIGO_BARRA.USUARIO_MOD_COBA   IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRO_CODIGO_BARRA.FECHA_MOD_COBA     IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PRO_PRODUCTO_SUCURSAL
CREATE TABLE PRO_PRODUCTO_SUCURSAL (
    ID_PRODUCTO_SUCURSAL  NUMBER(10)    DEFAULT SEQ_PRO_PRODUCTO_SUCURSAL.NEXTVAL NOT NULL,
    ID_PRODUCTO           NUMBER(10)    NOT NULL,
    ID_SUCURSAL           NUMBER(10)    NOT NULL,
    PORC_UTILIDAD_PRSU    NUMBER(5,2)   DEFAULT 0 NOT NULL,
    PORC_DESC_MAX_PRSU    NUMBER(5,2)   DEFAULT 0 NOT NULL,
    SE_VENDE_PRSU         VARCHAR2(1)   DEFAULT 'S' NOT NULL,
    ESTADO_PRSU           VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_PRSU     VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_PRSU       TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PRSU      VARCHAR2(30),
    FECHA_MOD_PRSU        TIMESTAMP,
    CONSTRAINT PK_PRSU PRIMARY KEY (ID_PRODUCTO_SUCURSAL)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_PRSU_PROD FOREIGN KEY (ID_PRODUCTO)
        REFERENCES PRO_PRODUCTO (ID_PRODUCTO),
    CONSTRAINT FK_PRSU_SUC FOREIGN KEY (ID_SUCURSAL)
        REFERENCES SEG_SUCURSAL (ID_SUCURSAL),
    CONSTRAINT UK_PRSU_PROD_SUC UNIQUE (ID_PRODUCTO, ID_SUCURSAL)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_PRSU_UTILIDAD CHECK (PORC_UTILIDAD_PRSU BETWEEN 0 AND 500),
    CONSTRAINT CK_PRSU_DESC_MAX CHECK (PORC_DESC_MAX_PRSU BETWEEN 0 AND 100),
    CONSTRAINT CK_PRSU_SE_VENDE CHECK (SE_VENDE_PRSU IN ('S','N')),
    CONSTRAINT CK_PRSU_ESTADO CHECK (ESTADO_PRSU IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRO_PRODUCTO_SUCURSAL                       IS 'Configuracion comercial de un producto en cada negocio (sucursal): porcentaje de utilidad y descuento maximo.';
COMMENT ON COLUMN PRO_PRODUCTO_SUCURSAL.ID_PRODUCTO_SUCURSAL  IS 'Identificador unico de la configuracion.';
COMMENT ON COLUMN PRO_PRODUCTO_SUCURSAL.ID_PRODUCTO           IS 'Producto configurado. FK a PRO_PRODUCTO.';
COMMENT ON COLUMN PRO_PRODUCTO_SUCURSAL.ID_SUCURSAL           IS 'Sucursal donde aplica. FK a SEG_SUCURSAL.';
COMMENT ON COLUMN PRO_PRODUCTO_SUCURSAL.PORC_UTILIDAD_PRSU    IS 'Porcentaje de utilidad sobre el costo en esta sucursal.';
COMMENT ON COLUMN PRO_PRODUCTO_SUCURSAL.PORC_DESC_MAX_PRSU    IS 'Porcentaje maximo de descuento permitido en esta sucursal.';
COMMENT ON COLUMN PRO_PRODUCTO_SUCURSAL.SE_VENDE_PRSU         IS 'Indica si el producto se vende en la sucursal: S=Si, N=No.';
COMMENT ON COLUMN PRO_PRODUCTO_SUCURSAL.ESTADO_PRSU           IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PRO_PRODUCTO_SUCURSAL.USUARIO_CREA_PRSU     IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRO_PRODUCTO_SUCURSAL.FECHA_CREA_PRSU       IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRO_PRODUCTO_SUCURSAL.USUARIO_MOD_PRSU      IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRO_PRODUCTO_SUCURSAL.FECHA_MOD_PRSU        IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PRO_PRECIO_HIST
CREATE TABLE PRO_PRECIO_HIST (
    ID_PRECIO_HIST       NUMBER(12)     DEFAULT SEQ_PRO_PRECIO_HIST.NEXTVAL NOT NULL,
    ID_PRODUCTO          NUMBER(10)     NOT NULL,
    COSTO_ANTERIOR_PRHI  NUMBER(14,4)   NOT NULL,
    FECHA_CAMBIO_PRHI    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    MOTIVO_PRHI          VARCHAR2(200),
    USUARIO_CREA_PRHI    VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_PRHI      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT PK_PRHI PRIMARY KEY (ID_PRECIO_HIST)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_PRHI_PROD FOREIGN KEY (ID_PRODUCTO)
        REFERENCES PRO_PRODUCTO (ID_PRODUCTO),
    CONSTRAINT UK_PRHI_PROD_FECHA UNIQUE (ID_PRODUCTO, FECHA_CAMBIO_PRHI)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_PRHI_COSTO CHECK (COSTO_ANTERIOR_PRHI >= 0)
) TABLESPACE TBS_AUDITORIA;

COMMENT ON TABLE  PRO_PRECIO_HIST                      IS 'Bitacora de cambios de precio de costo. Cada fila guarda el costo que dejo de regir; el costo vigente esta en PRO_PRODUCTO, por lo que no hay datos duplicados.';
COMMENT ON COLUMN PRO_PRECIO_HIST.ID_PRECIO_HIST       IS 'Identificador unico del cambio.';
COMMENT ON COLUMN PRO_PRECIO_HIST.ID_PRODUCTO          IS 'Producto cuyo costo cambio. FK a PRO_PRODUCTO.';
COMMENT ON COLUMN PRO_PRECIO_HIST.COSTO_ANTERIOR_PRHI  IS 'Precio de costo que regia hasta la fecha del cambio.';
COMMENT ON COLUMN PRO_PRECIO_HIST.FECHA_CAMBIO_PRHI    IS 'Fecha y hora en que el costo anterior dejo de regir.';
COMMENT ON COLUMN PRO_PRECIO_HIST.MOTIVO_PRHI          IS 'Motivo del cambio de precio.';
COMMENT ON COLUMN PRO_PRECIO_HIST.USUARIO_CREA_PRHI    IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRO_PRECIO_HIST.FECHA_CREA_PRHI      IS 'Fecha y hora de creacion del registro.';

-- TABLA: PRO_LOTE
CREATE TABLE PRO_LOTE (
    ID_LOTE             NUMBER(12)    DEFAULT SEQ_PRO_LOTE.NEXTVAL NOT NULL,
    ID_PRODUCTO         NUMBER(10)    NOT NULL,
    NUMERO_LOTE         VARCHAR2(30)  NOT NULL,
    FECHA_INGRESO_LOTE  DATE          DEFAULT SYSDATE NOT NULL,
    FECHA_VENCIM_LOTE   DATE,
    FECHA_FABRIC_LOTE   DATE,
    ESTADO_LOTE         VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_LOTE   VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_LOTE     TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_LOTE    VARCHAR2(30),
    FECHA_MOD_LOTE      TIMESTAMP,
    CONSTRAINT PK_LOTE PRIMARY KEY (ID_LOTE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_LOTE_PROD FOREIGN KEY (ID_PRODUCTO)
        REFERENCES PRO_PRODUCTO (ID_PRODUCTO),
    CONSTRAINT UK_LOTE_PROD_NUM UNIQUE (ID_PRODUCTO, NUMERO_LOTE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT UK_LOTE_ID_PROD UNIQUE (ID_LOTE, ID_PRODUCTO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_LOTE_FECHAS CHECK (FECHA_VENCIM_LOTE IS NULL OR FECHA_VENCIM_LOTE > FECHA_INGRESO_LOTE),
    CONSTRAINT CK_LOTE_FABRIC CHECK (FECHA_FABRIC_LOTE IS NULL OR FECHA_FABRIC_LOTE <= FECHA_INGRESO_LOTE),
    CONSTRAINT CK_LOTE_ESTADO CHECK (ESTADO_LOTE IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRO_LOTE                     IS 'Lotes de un producto. Guarda la fecha de ingreso y la fecha de vencimiento.';
COMMENT ON COLUMN PRO_LOTE.ID_LOTE             IS 'Identificador unico del lote.';
COMMENT ON COLUMN PRO_LOTE.ID_PRODUCTO         IS 'Producto al que pertenece el lote. FK a PRO_PRODUCTO.';
COMMENT ON COLUMN PRO_LOTE.NUMERO_LOTE         IS 'Numero de lote asignado por el fabricante o el negocio.';
COMMENT ON COLUMN PRO_LOTE.FECHA_INGRESO_LOTE  IS 'Fecha de ingreso del lote al inventario.';
COMMENT ON COLUMN PRO_LOTE.FECHA_VENCIM_LOTE   IS 'Fecha de vencimiento. Nulo en productos no perecederos.';
COMMENT ON COLUMN PRO_LOTE.FECHA_FABRIC_LOTE   IS 'Fecha de fabricacion.';
COMMENT ON COLUMN PRO_LOTE.ESTADO_LOTE         IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PRO_LOTE.USUARIO_CREA_LOTE   IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRO_LOTE.FECHA_CREA_LOTE     IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRO_LOTE.USUARIO_MOD_LOTE    IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRO_LOTE.FECHA_MOD_LOTE      IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PRO_SERVICIO
CREATE TABLE PRO_SERVICIO (
    ID_SERVICIO        NUMBER(10)     DEFAULT SEQ_PRO_SERVICIO.NEXTVAL NOT NULL,
    ID_IMPUESTO        NUMBER(10),
    CODIGO_SERV        VARCHAR2(20)   NOT NULL,
    NOMBRE_SERV        VARCHAR2(150)  NOT NULL,
    DESCRIPCION_SERV   VARCHAR2(250),
    PRECIO_SERV        NUMBER(14,4)   DEFAULT 0 NOT NULL,
    ES_EXENTO_SERV     VARCHAR2(1)    GENERATED ALWAYS AS (CASE WHEN ID_IMPUESTO IS NULL THEN 'S' ELSE 'N' END) VIRTUAL,
    ESTADO_SERV        VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_SERV  VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_SERV    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_SERV   VARCHAR2(30),
    FECHA_MOD_SERV     TIMESTAMP,
    CONSTRAINT PK_SERV PRIMARY KEY (ID_SERVICIO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_SERV_IMPU FOREIGN KEY (ID_IMPUESTO)
        REFERENCES PRO_IMPUESTO (ID_IMPUESTO),
    CONSTRAINT UK_SERV_CODIGO UNIQUE (CODIGO_SERV)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_SERV_PRECIO CHECK (PRECIO_SERV >= 0),
    CONSTRAINT CK_SERV_ESTADO CHECK (ESTADO_SERV IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRO_SERVICIO                    IS 'Servicios que el punto de venta puede facturar ademas de los productos.';
COMMENT ON COLUMN PRO_SERVICIO.ID_SERVICIO        IS 'Identificador unico del servicio.';
COMMENT ON COLUMN PRO_SERVICIO.ID_IMPUESTO        IS 'Impuesto que grava el servicio. FK a PRO_IMPUESTO. Nulo significa servicio exento.';
COMMENT ON COLUMN PRO_SERVICIO.CODIGO_SERV        IS 'Codigo interno del servicio.';
COMMENT ON COLUMN PRO_SERVICIO.NOMBRE_SERV        IS 'Nombre del servicio.';
COMMENT ON COLUMN PRO_SERVICIO.DESCRIPCION_SERV   IS 'Descripcion ampliada.';
COMMENT ON COLUMN PRO_SERVICIO.PRECIO_SERV        IS 'Precio del servicio sin impuesto.';
COMMENT ON COLUMN PRO_SERVICIO.ES_EXENTO_SERV     IS 'Columna virtual: S si el servicio es exento de impuestos, N si es gravado.';
COMMENT ON COLUMN PRO_SERVICIO.ESTADO_SERV        IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PRO_SERVICIO.USUARIO_CREA_SERV  IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRO_SERVICIO.FECHA_CREA_SERV    IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRO_SERVICIO.USUARIO_MOD_SERV   IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRO_SERVICIO.FECHA_MOD_SERV     IS 'Fecha y hora de la ultima modificacion.';

-- VISTA: V_PRECIO_VENTA
CREATE OR REPLACE VIEW V_PRECIO_VENTA AS
SELECT p.ID_PRODUCTO,
       ps.ID_SUCURSAL,
       p.CODIGO_PROD,
       p.NOMBRE_PROD,
       p.PRECIO_COSTO_PROD                                        AS COSTO,
       ps.PORC_UTILIDAD_PRSU                                      AS UTILIDAD,
       ps.PORC_DESC_MAX_PRSU                                      AS DESCUENTO_MAX,
       p.ES_EXENTO_PROD                                           AS ES_EXENTO,
       NVL(i.PORCENTAJE_IMPU, 0)                                  AS TASA_IMPUESTO,
       ROUND(p.PRECIO_COSTO_PROD *
             (1 + ps.PORC_UTILIDAD_PRSU / 100), 2)                AS PRECIO_SIN_IMPUESTO,
       ROUND(p.PRECIO_COSTO_PROD *
             (1 + ps.PORC_UTILIDAD_PRSU / 100) *
             (1 + NVL(i.PORCENTAJE_IMPU, 0) / 100), 2)            AS PRECIO_VENTA,
       ROUND(p.PRECIO_COSTO_PROD *
             (1 + ps.PORC_UTILIDAD_PRSU / 100) *
             (1 - ps.PORC_DESC_MAX_PRSU / 100) *
             (1 + NVL(i.PORCENTAJE_IMPU, 0) / 100), 2)            AS PRECIO_MIN_VENTA
  FROM PRO_PRODUCTO p
       JOIN PRO_PRODUCTO_SUCURSAL ps ON ps.ID_PRODUCTO = p.ID_PRODUCTO
       LEFT JOIN PRO_IMPUESTO i ON i.ID_IMPUESTO = p.ID_IMPUESTO
 WHERE p.ESTADO_PROD = 'A'
   AND ps.ESTADO_PRSU = 'A';

COMMENT ON TABLE V_PRECIO_VENTA IS 'Calcula el precio de venta de cada producto por sucursal a partir del costo, la utilidad, el descuento maximo y el impuesto. El precio de venta no se almacena.';

PROMPT Modulo PRO_ creado: 8 tablas, 8 secuencias, 1 vistas.


--------------------------------------------------------------------------------
-- SECCION 6 de 12: modulo INV_
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Bodegas, existencias, movimientos y traslados
--------------------------------------------------------------------------------
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SECUENCIAS DEL MODULO
CREATE SEQUENCE SEQ_INV_BODEGA         START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_INV_EXISTENCIA     START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_INV_MOVIMIENTO     START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_INV_MOVIMIENTO_DET  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_INV_TRASLADO       START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_INV_TRASLADO_DET   START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- TABLA: INV_BODEGA
CREATE TABLE INV_BODEGA (
    ID_BODEGA            NUMBER(10)     DEFAULT SEQ_INV_BODEGA.NEXTVAL NOT NULL,
    ID_SUCURSAL          NUMBER(10),
    CODIGO_BODE          VARCHAR2(20)   NOT NULL,
    NOMBRE_BODE          VARCHAR2(100)  NOT NULL,
    ES_CENTRAL_BODE      VARCHAR2(1)    GENERATED ALWAYS AS (CASE WHEN ID_SUCURSAL IS NULL THEN 'S' ELSE 'N' END) VIRTUAL,
    SENNAS_EXACTAS_BODE  VARCHAR2(250),
    ESTADO_BODE          VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_BODE    VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_BODE      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_BODE     VARCHAR2(30),
    FECHA_MOD_BODE       TIMESTAMP,
    CONSTRAINT PK_BODE PRIMARY KEY (ID_BODEGA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_BODE_SUC FOREIGN KEY (ID_SUCURSAL)
        REFERENCES SEG_SUCURSAL (ID_SUCURSAL),
    CONSTRAINT UK_BODE_CODIGO UNIQUE (CODIGO_BODE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_BODE_ESTADO CHECK (ESTADO_BODE IN ('A','I'))
) TABLESPACE TBS_DATOS;

CREATE UNIQUE INDEX UX_BODE_CENTRAL
    ON INV_BODEGA (CASE WHEN ID_SUCURSAL IS NULL THEN 1 END)
    TABLESPACE TBS_INDICES;

COMMENT ON TABLE  INV_BODEGA                      IS 'Bodegas. El inventario esta centralizado en la bodega central (sin sucursal) y desde ella se traslada a las bodegas de cada sucursal.';
COMMENT ON COLUMN INV_BODEGA.ID_BODEGA            IS 'Identificador unico de la bodega.';
COMMENT ON COLUMN INV_BODEGA.ID_SUCURSAL          IS 'Sucursal a la que pertenece. FK a SEG_SUCURSAL. Nulo unicamente en la bodega central.';
COMMENT ON COLUMN INV_BODEGA.CODIGO_BODE          IS 'Codigo interno de la bodega.';
COMMENT ON COLUMN INV_BODEGA.NOMBRE_BODE          IS 'Nombre de la bodega.';
COMMENT ON COLUMN INV_BODEGA.ES_CENTRAL_BODE      IS 'Columna virtual: S si es la bodega central (no pertenece a ninguna sucursal), N en caso contrario.';
COMMENT ON COLUMN INV_BODEGA.SENNAS_EXACTAS_BODE  IS 'Senas exactas de la bodega.';
COMMENT ON COLUMN INV_BODEGA.ESTADO_BODE          IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN INV_BODEGA.USUARIO_CREA_BODE    IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN INV_BODEGA.FECHA_CREA_BODE      IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN INV_BODEGA.USUARIO_MOD_BODE     IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN INV_BODEGA.FECHA_MOD_BODE       IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: INV_EXISTENCIA
CREATE TABLE INV_EXISTENCIA (
    ID_EXISTENCIA         NUMBER(12)    DEFAULT SEQ_INV_EXISTENCIA.NEXTVAL NOT NULL,
    ID_BODEGA             NUMBER(10)    NOT NULL,
    ID_PRODUCTO           NUMBER(10)    NOT NULL,
    ID_LOTE               NUMBER(12),
    CANTIDAD_EXIS         NUMBER(14,3)  DEFAULT 0 NOT NULL,
    CANTIDAD_RESERV_EXIS  NUMBER(14,3)  DEFAULT 0 NOT NULL,
    USUARIO_CREA_EXIS     VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_EXIS       TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_EXIS      VARCHAR2(30),
    FECHA_MOD_EXIS        TIMESTAMP,
    CONSTRAINT PK_EXIS PRIMARY KEY (ID_EXISTENCIA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_EXIS_BODE FOREIGN KEY (ID_BODEGA)
        REFERENCES INV_BODEGA (ID_BODEGA),
    CONSTRAINT FK_EXIS_PROD FOREIGN KEY (ID_PRODUCTO)
        REFERENCES PRO_PRODUCTO (ID_PRODUCTO),
    CONSTRAINT FK_EXIS_LOTE FOREIGN KEY (ID_LOTE, ID_PRODUCTO)
        REFERENCES PRO_LOTE (ID_LOTE, ID_PRODUCTO),
    CONSTRAINT UK_EXIS_BODE_PROD_LOTE UNIQUE (ID_BODEGA, ID_PRODUCTO, ID_LOTE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_EXIS_CANTIDAD CHECK (CANTIDAD_EXIS >= 0),
    CONSTRAINT CK_EXIS_RESERVADA CHECK (CANTIDAD_RESERV_EXIS >= 0 AND CANTIDAD_RESERV_EXIS <= CANTIDAD_EXIS)
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  INV_EXISTENCIA                       IS 'Existencia de cada producto (y lote, si aplica) en cada bodega.';
COMMENT ON COLUMN INV_EXISTENCIA.ID_EXISTENCIA         IS 'Identificador unico del registro de existencia.';
COMMENT ON COLUMN INV_EXISTENCIA.ID_BODEGA             IS 'Bodega donde esta el producto. FK a INV_BODEGA.';
COMMENT ON COLUMN INV_EXISTENCIA.ID_PRODUCTO           IS 'Producto en existencia. FK a PRO_PRODUCTO.';
COMMENT ON COLUMN INV_EXISTENCIA.ID_LOTE               IS 'Lote en existencia. FK compuesta a PRO_LOTE junto con ID_PRODUCTO, lo que garantiza que el lote sea de ese producto.';
COMMENT ON COLUMN INV_EXISTENCIA.CANTIDAD_EXIS         IS 'Cantidad disponible.';
COMMENT ON COLUMN INV_EXISTENCIA.CANTIDAD_RESERV_EXIS  IS 'Cantidad reservada para traslados pendientes.';
COMMENT ON COLUMN INV_EXISTENCIA.USUARIO_CREA_EXIS     IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN INV_EXISTENCIA.FECHA_CREA_EXIS       IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN INV_EXISTENCIA.USUARIO_MOD_EXIS      IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN INV_EXISTENCIA.FECHA_MOD_EXIS        IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: INV_MOVIMIENTO
CREATE TABLE INV_MOVIMIENTO (
    ID_MOVIMIENTO       NUMBER(12)     DEFAULT SEQ_INV_MOVIMIENTO.NEXTVAL NOT NULL,
    ID_BODEGA           NUMBER(10)     NOT NULL,
    ID_USUARIO          NUMBER(10)     NOT NULL,
    TIPO_MOVI           VARCHAR2(10)   NOT NULL,
    CONSECUTIVO_MOVI    VARCHAR2(20)   NOT NULL,
    FECHA_MOVI          DATE           DEFAULT SYSDATE NOT NULL,
    DOCUMENTO_REF_MOVI  VARCHAR2(30),
    OBSERVACION_MOVI    VARCHAR2(250),
    ESTADO_MOVI         VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_MOVI   VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_MOVI     TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_MOVI    VARCHAR2(30),
    FECHA_MOD_MOVI      TIMESTAMP,
    CONSTRAINT PK_MOVI PRIMARY KEY (ID_MOVIMIENTO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_MOVI_BODE FOREIGN KEY (ID_BODEGA)
        REFERENCES INV_BODEGA (ID_BODEGA),
    CONSTRAINT FK_MOVI_USU FOREIGN KEY (ID_USUARIO)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT UK_MOVI_CONSECUTIVO UNIQUE (CONSECUTIVO_MOVI)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_MOVI_TIPO CHECK (TIPO_MOVI IN ('COMPRA','VENTA','TRASL_ENT','TRASL_SAL','AJUSTE_ENT','AJUSTE_SAL','DEVOL_CLI','DEVOL_PROV')),
    CONSTRAINT CK_MOVI_ESTADO CHECK (ESTADO_MOVI IN ('A','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  INV_MOVIMIENTO                     IS 'Encabezado de los movimientos de inventario (kardex) de una bodega.';
COMMENT ON COLUMN INV_MOVIMIENTO.ID_MOVIMIENTO       IS 'Identificador unico del movimiento.';
COMMENT ON COLUMN INV_MOVIMIENTO.ID_BODEGA           IS 'Bodega afectada. FK a INV_BODEGA.';
COMMENT ON COLUMN INV_MOVIMIENTO.ID_USUARIO          IS 'Usuario que registro el movimiento. FK a SEG_USUARIO.';
COMMENT ON COLUMN INV_MOVIMIENTO.TIPO_MOVI           IS 'Tipo: COMPRA, TRASL_ENT, AJUSTE_ENT y DEVOL_CLI son entradas; VENTA, TRASL_SAL, AJUSTE_SAL y DEVOL_PROV son salidas.';
COMMENT ON COLUMN INV_MOVIMIENTO.CONSECUTIVO_MOVI    IS 'Consecutivo interno del movimiento.';
COMMENT ON COLUMN INV_MOVIMIENTO.FECHA_MOVI          IS 'Fecha del movimiento.';
COMMENT ON COLUMN INV_MOVIMIENTO.DOCUMENTO_REF_MOVI  IS 'Numero del documento que origino el movimiento (factura, traslado, ajuste).';
COMMENT ON COLUMN INV_MOVIMIENTO.OBSERVACION_MOVI    IS 'Observaciones.';
COMMENT ON COLUMN INV_MOVIMIENTO.ESTADO_MOVI         IS 'Estado del registro: A=Activo, N=Anulado.';
COMMENT ON COLUMN INV_MOVIMIENTO.USUARIO_CREA_MOVI   IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN INV_MOVIMIENTO.FECHA_CREA_MOVI     IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN INV_MOVIMIENTO.USUARIO_MOD_MOVI    IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN INV_MOVIMIENTO.FECHA_MOD_MOVI      IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: INV_MOVIMIENTO_DET
CREATE TABLE INV_MOVIMIENTO_DET (
    ID_MOVIMIENTO_DET    NUMBER(12)    DEFAULT SEQ_INV_MOVIMIENTO_DET.NEXTVAL NOT NULL,
    ID_MOVIMIENTO        NUMBER(12)    NOT NULL,
    ID_PRODUCTO          NUMBER(10)    NOT NULL,
    ID_LOTE              NUMBER(12),
    LINEA_MODE           NUMBER(4)     NOT NULL,
    CANTIDAD_MODE        NUMBER(14,3)  NOT NULL,
    COSTO_UNITARIO_MODE  NUMBER(14,4)  DEFAULT 0 NOT NULL,
    USUARIO_CREA_MODE    VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_MODE      TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_MODE     VARCHAR2(30),
    FECHA_MOD_MODE       TIMESTAMP,
    CONSTRAINT PK_MODE PRIMARY KEY (ID_MOVIMIENTO_DET)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_MODE_MOVI FOREIGN KEY (ID_MOVIMIENTO)
        REFERENCES INV_MOVIMIENTO (ID_MOVIMIENTO),
    CONSTRAINT FK_MODE_PROD FOREIGN KEY (ID_PRODUCTO)
        REFERENCES PRO_PRODUCTO (ID_PRODUCTO),
    CONSTRAINT FK_MODE_LOTE FOREIGN KEY (ID_LOTE, ID_PRODUCTO)
        REFERENCES PRO_LOTE (ID_LOTE, ID_PRODUCTO),
    CONSTRAINT UK_MODE_MOVI_LINEA UNIQUE (ID_MOVIMIENTO, LINEA_MODE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_MODE_CANTIDAD CHECK (CANTIDAD_MODE > 0),
    CONSTRAINT CK_MODE_COSTO CHECK (COSTO_UNITARIO_MODE >= 0),
    CONSTRAINT CK_MODE_LINEA CHECK (LINEA_MODE > 0)
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  INV_MOVIMIENTO_DET                      IS 'Detalle de productos de un movimiento de inventario. Los saldos no se almacenan: se calculan en V_KARDEX.';
COMMENT ON COLUMN INV_MOVIMIENTO_DET.ID_MOVIMIENTO_DET    IS 'Identificador unico de la linea.';
COMMENT ON COLUMN INV_MOVIMIENTO_DET.ID_MOVIMIENTO        IS 'Movimiento al que pertenece. FK a INV_MOVIMIENTO.';
COMMENT ON COLUMN INV_MOVIMIENTO_DET.ID_PRODUCTO          IS 'Producto movido. FK a PRO_PRODUCTO.';
COMMENT ON COLUMN INV_MOVIMIENTO_DET.ID_LOTE              IS 'Lote movido. FK compuesta a PRO_LOTE junto con ID_PRODUCTO.';
COMMENT ON COLUMN INV_MOVIMIENTO_DET.LINEA_MODE           IS 'Numero de linea dentro del movimiento.';
COMMENT ON COLUMN INV_MOVIMIENTO_DET.CANTIDAD_MODE        IS 'Cantidad movida, siempre positiva. El signo lo da el tipo de movimiento.';
COMMENT ON COLUMN INV_MOVIMIENTO_DET.COSTO_UNITARIO_MODE  IS 'Costo unitario al momento del movimiento.';
COMMENT ON COLUMN INV_MOVIMIENTO_DET.USUARIO_CREA_MODE    IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN INV_MOVIMIENTO_DET.FECHA_CREA_MODE      IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN INV_MOVIMIENTO_DET.USUARIO_MOD_MODE     IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN INV_MOVIMIENTO_DET.FECHA_MOD_MODE       IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: INV_TRASLADO
CREATE TABLE INV_TRASLADO (
    ID_TRASLADO           NUMBER(12)     DEFAULT SEQ_INV_TRASLADO.NEXTVAL NOT NULL,
    ID_BODEGA_ORIGEN      NUMBER(10)     NOT NULL,
    ID_BODEGA_DESTINO     NUMBER(10)     NOT NULL,
    ID_USUARIO_ENVIA      NUMBER(10)     NOT NULL,
    ID_USUARIO_RECIBE     NUMBER(10),
    CONSECUTIVO_TRAS      VARCHAR2(20)   NOT NULL,
    FECHA_ENVIO_TRAS      DATE           DEFAULT SYSDATE NOT NULL,
    FECHA_RECEPCION_TRAS  DATE,
    OBSERVACION_TRAS      VARCHAR2(250),
    ESTADO_TRAS           VARCHAR2(1)    DEFAULT 'P' NOT NULL,
    USUARIO_CREA_TRAS     VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_TRAS       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_TRAS      VARCHAR2(30),
    FECHA_MOD_TRAS        TIMESTAMP,
    CONSTRAINT PK_TRAS PRIMARY KEY (ID_TRASLADO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_TRAS_BODE_ORI FOREIGN KEY (ID_BODEGA_ORIGEN)
        REFERENCES INV_BODEGA (ID_BODEGA),
    CONSTRAINT FK_TRAS_BODE_DES FOREIGN KEY (ID_BODEGA_DESTINO)
        REFERENCES INV_BODEGA (ID_BODEGA),
    CONSTRAINT FK_TRAS_USU_ENV FOREIGN KEY (ID_USUARIO_ENVIA)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT FK_TRAS_USU_REC FOREIGN KEY (ID_USUARIO_RECIBE)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT UK_TRAS_CONSECUTIVO UNIQUE (CONSECUTIVO_TRAS)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_TRAS_BODEGAS CHECK (ID_BODEGA_ORIGEN <> ID_BODEGA_DESTINO),
    CONSTRAINT CK_TRAS_FECHAS CHECK (FECHA_RECEPCION_TRAS IS NULL OR FECHA_RECEPCION_TRAS >= FECHA_ENVIO_TRAS),
    CONSTRAINT CK_TRAS_RECEPCION CHECK (
            (ESTADO_TRAS = 'R' AND ID_USUARIO_RECIBE IS NOT NULL AND FECHA_RECEPCION_TRAS IS NOT NULL)
            OR (ESTADO_TRAS <> 'R' AND FECHA_RECEPCION_TRAS IS NULL)
        ),
    CONSTRAINT CK_TRAS_ESTADO CHECK (ESTADO_TRAS IN ('P','T','R','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  INV_TRASLADO                       IS 'Encabezado de los traslados de productos entre bodegas (de la bodega central a las sucursales).';
COMMENT ON COLUMN INV_TRASLADO.ID_TRASLADO           IS 'Identificador unico del traslado.';
COMMENT ON COLUMN INV_TRASLADO.ID_BODEGA_ORIGEN      IS 'Bodega que envia. FK a INV_BODEGA (rol: origen).';
COMMENT ON COLUMN INV_TRASLADO.ID_BODEGA_DESTINO     IS 'Bodega que recibe. FK a INV_BODEGA (rol: destino).';
COMMENT ON COLUMN INV_TRASLADO.ID_USUARIO_ENVIA      IS 'Usuario que despacha. FK a SEG_USUARIO (rol: envia).';
COMMENT ON COLUMN INV_TRASLADO.ID_USUARIO_RECIBE     IS 'Usuario que recibe. FK a SEG_USUARIO (rol: recibe). Nulo mientras no se reciba.';
COMMENT ON COLUMN INV_TRASLADO.CONSECUTIVO_TRAS      IS 'Consecutivo interno del traslado.';
COMMENT ON COLUMN INV_TRASLADO.FECHA_ENVIO_TRAS      IS 'Fecha de envio.';
COMMENT ON COLUMN INV_TRASLADO.FECHA_RECEPCION_TRAS  IS 'Fecha de recepcion.';
COMMENT ON COLUMN INV_TRASLADO.OBSERVACION_TRAS      IS 'Observaciones.';
COMMENT ON COLUMN INV_TRASLADO.ESTADO_TRAS           IS 'Estado del registro: P=Pendiente, T=En transito, R=Recibido, N=Anulado.';
COMMENT ON COLUMN INV_TRASLADO.USUARIO_CREA_TRAS     IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN INV_TRASLADO.FECHA_CREA_TRAS       IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN INV_TRASLADO.USUARIO_MOD_TRAS      IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN INV_TRASLADO.FECHA_MOD_TRAS        IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: INV_TRASLADO_DET
CREATE TABLE INV_TRASLADO_DET (
    ID_TRASLADO_DET       NUMBER(12)     DEFAULT SEQ_INV_TRASLADO_DET.NEXTVAL NOT NULL,
    ID_TRASLADO           NUMBER(12)     NOT NULL,
    ID_PRODUCTO           NUMBER(10)     NOT NULL,
    ID_LOTE               NUMBER(12),
    LINEA_TRDE            NUMBER(4)      NOT NULL,
    CANTIDAD_ENVIA_TRDE   NUMBER(14,3)   NOT NULL,
    CANTIDAD_RECIBE_TRDE  NUMBER(14,3),
    OBSERVACION_TRDE      VARCHAR2(200),
    USUARIO_CREA_TRDE     VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_TRDE       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_TRDE      VARCHAR2(30),
    FECHA_MOD_TRDE        TIMESTAMP,
    CONSTRAINT PK_TRDE PRIMARY KEY (ID_TRASLADO_DET)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_TRDE_TRAS FOREIGN KEY (ID_TRASLADO)
        REFERENCES INV_TRASLADO (ID_TRASLADO),
    CONSTRAINT FK_TRDE_PROD FOREIGN KEY (ID_PRODUCTO)
        REFERENCES PRO_PRODUCTO (ID_PRODUCTO),
    CONSTRAINT FK_TRDE_LOTE FOREIGN KEY (ID_LOTE, ID_PRODUCTO)
        REFERENCES PRO_LOTE (ID_LOTE, ID_PRODUCTO),
    CONSTRAINT UK_TRDE_TRAS_LINEA UNIQUE (ID_TRASLADO, LINEA_TRDE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_TRDE_CANT_ENVIA CHECK (CANTIDAD_ENVIA_TRDE > 0),
    CONSTRAINT CK_TRDE_CANT_RECIBE CHECK (CANTIDAD_RECIBE_TRDE IS NULL OR (CANTIDAD_RECIBE_TRDE >= 0 AND CANTIDAD_RECIBE_TRDE <= CANTIDAD_ENVIA_TRDE)),
    CONSTRAINT CK_TRDE_LINEA CHECK (LINEA_TRDE > 0)
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  INV_TRASLADO_DET                       IS 'Detalle de productos de un traslado entre bodegas.';
COMMENT ON COLUMN INV_TRASLADO_DET.ID_TRASLADO_DET       IS 'Identificador unico de la linea.';
COMMENT ON COLUMN INV_TRASLADO_DET.ID_TRASLADO           IS 'Traslado al que pertenece. FK a INV_TRASLADO.';
COMMENT ON COLUMN INV_TRASLADO_DET.ID_PRODUCTO           IS 'Producto trasladado. FK a PRO_PRODUCTO.';
COMMENT ON COLUMN INV_TRASLADO_DET.ID_LOTE               IS 'Lote trasladado. FK compuesta a PRO_LOTE junto con ID_PRODUCTO.';
COMMENT ON COLUMN INV_TRASLADO_DET.LINEA_TRDE            IS 'Numero de linea dentro del traslado.';
COMMENT ON COLUMN INV_TRASLADO_DET.CANTIDAD_ENVIA_TRDE   IS 'Cantidad enviada.';
COMMENT ON COLUMN INV_TRASLADO_DET.CANTIDAD_RECIBE_TRDE  IS 'Cantidad recibida. Nulo mientras no se reciba.';
COMMENT ON COLUMN INV_TRASLADO_DET.OBSERVACION_TRDE      IS 'Observaciones de la linea (faltantes, danos).';
COMMENT ON COLUMN INV_TRASLADO_DET.USUARIO_CREA_TRDE     IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN INV_TRASLADO_DET.FECHA_CREA_TRDE       IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN INV_TRASLADO_DET.USUARIO_MOD_TRDE      IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN INV_TRASLADO_DET.FECHA_MOD_TRDE        IS 'Fecha y hora de la ultima modificacion.';

-- VISTA: V_KARDEX
CREATE OR REPLACE VIEW V_KARDEX AS
SELECT m.ID_BODEGA,
       b.NOMBRE_BODE,
       d.ID_PRODUCTO,
       p.CODIGO_PROD,
       p.NOMBRE_PROD,
       m.TIPO_MOVI,
       m.FECHA_MOVI,
       m.CONSECUTIVO_MOVI,
       m.DOCUMENTO_REF_MOVI,
       d.CANTIDAD_MODE * CASE WHEN m.TIPO_MOVI IN ('COMPRA','TRASL_ENT','AJUSTE_ENT','DEVOL_CLI') THEN 1 ELSE -1 END  AS CANTIDAD_CON_SIGNO,
       d.COSTO_UNITARIO_MODE,
       d.CANTIDAD_MODE * d.COSTO_UNITARIO_MODE                    AS VALOR_MOVIMIENTO,
       SUM(d.CANTIDAD_MODE * CASE WHEN m.TIPO_MOVI IN ('COMPRA','TRASL_ENT','AJUSTE_ENT','DEVOL_CLI') THEN 1 ELSE -1 END)
           OVER (PARTITION BY m.ID_BODEGA, d.ID_PRODUCTO
                 ORDER BY m.FECHA_MOVI, d.ID_MOVIMIENTO_DET)      AS SALDO_ACUMULADO
  FROM INV_MOVIMIENTO m
       JOIN INV_MOVIMIENTO_DET d ON d.ID_MOVIMIENTO = m.ID_MOVIMIENTO
       JOIN INV_BODEGA b         ON b.ID_BODEGA     = m.ID_BODEGA
       JOIN PRO_PRODUCTO p       ON p.ID_PRODUCTO   = d.ID_PRODUCTO
 WHERE m.ESTADO_MOVI = 'A';

COMMENT ON TABLE V_KARDEX IS 'Kardex por bodega y producto. La cantidad con signo y el saldo acumulado se calculan; no se almacenan.';

PROMPT Modulo INV_ creado: 6 tablas, 6 secuencias, 1 vistas.


--------------------------------------------------------------------------------
-- SECCION 7 de 12: modulo COM_
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Compras, cuentas por pagar y devoluciones a proveedores
--------------------------------------------------------------------------------
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SECUENCIAS DEL MODULO
CREATE SEQUENCE SEQ_COM_FACTURA_COMPRA     START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_COM_FACTURA_COMPRA_DET  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_COM_ABONO_PAGAR        START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_COM_DEVOLUCION         START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_COM_DEVOLUCION_DET     START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_COM_NOTA_CREDITO       START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- TABLA: COM_FACTURA_COMPRA
CREATE TABLE COM_FACTURA_COMPRA (
    ID_FACTURA_COMPRA  NUMBER(12)     DEFAULT SEQ_COM_FACTURA_COMPRA.NEXTVAL NOT NULL,
    ID_PROVEEDOR       NUMBER(10)     NOT NULL,
    ID_BODEGA          NUMBER(10)     NOT NULL,
    ID_USUARIO         NUMBER(10)     NOT NULL,
    NUM_FACTURA_FACO   VARCHAR2(30)   NOT NULL,
    FECHA_FACO         DATE           DEFAULT SYSDATE NOT NULL,
    ES_CREDITO_FACO    VARCHAR2(1)    DEFAULT 'N' NOT NULL,
    FECHA_VENCIM_FACO  DATE,
    SUBTOTAL_FACO      NUMBER(14,2)   DEFAULT 0 NOT NULL,
    DESCUENTO_FACO     NUMBER(14,2)   DEFAULT 0 NOT NULL,
    IMPUESTO_FACO      NUMBER(14,2)   DEFAULT 0 NOT NULL,
    TOTAL_FACO         NUMBER(14,2)   GENERATED ALWAYS AS (SUBTOTAL_FACO - DESCUENTO_FACO + IMPUESTO_FACO) VIRTUAL,
    OBSERVACION_FACO   VARCHAR2(250),
    ESTADO_FACO        VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_FACO  VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_FACO    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_FACO   VARCHAR2(30),
    FECHA_MOD_FACO     TIMESTAMP,
    CONSTRAINT PK_FACO PRIMARY KEY (ID_FACTURA_COMPRA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_FACO_PROVE FOREIGN KEY (ID_PROVEEDOR)
        REFERENCES PER_PROVEEDOR (ID_PROVEEDOR),
    CONSTRAINT FK_FACO_BODE FOREIGN KEY (ID_BODEGA)
        REFERENCES INV_BODEGA (ID_BODEGA),
    CONSTRAINT FK_FACO_USU FOREIGN KEY (ID_USUARIO)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT UK_FACO_PROVE_NUM UNIQUE (ID_PROVEEDOR, NUM_FACTURA_FACO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_FACO_SUBTOTAL CHECK (SUBTOTAL_FACO >= 0),
    CONSTRAINT CK_FACO_DESCUENTO CHECK (DESCUENTO_FACO >= 0 AND DESCUENTO_FACO <= SUBTOTAL_FACO),
    CONSTRAINT CK_FACO_IMPUESTO CHECK (IMPUESTO_FACO >= 0),
    CONSTRAINT CK_FACO_CRED_VENCIM CHECK (ES_CREDITO_FACO = 'N' OR FECHA_VENCIM_FACO IS NOT NULL),
    CONSTRAINT CK_FACO_FECHAS CHECK (FECHA_VENCIM_FACO IS NULL OR FECHA_VENCIM_FACO >= FECHA_FACO),
    CONSTRAINT CK_FACO_CREDITO CHECK (ES_CREDITO_FACO IN ('S','N')),
    CONSTRAINT CK_FACO_ESTADO CHECK (ESTADO_FACO IN ('A','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  COM_FACTURA_COMPRA                    IS 'Facturas de compra a proveedores. Una factura a credito con saldo es una cuenta por pagar (ver V_CUENTA_PAGAR). Los totales se guardan porque el enunciado lo exige.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.ID_FACTURA_COMPRA  IS 'Identificador unico de la factura de compra.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.ID_PROVEEDOR       IS 'Proveedor que emite la factura. FK a PER_PROVEEDOR.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.ID_BODEGA          IS 'Bodega que recibe la mercaderia (normalmente la central). FK a INV_BODEGA.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.ID_USUARIO         IS 'Usuario que registro la compra. FK a SEG_USUARIO.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.NUM_FACTURA_FACO   IS 'Numero de factura del proveedor.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.FECHA_FACO         IS 'Fecha de la factura.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.ES_CREDITO_FACO    IS 'Indica si la compra queda pendiente de pago: S=Credito, N=Contado.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.FECHA_VENCIM_FACO  IS 'Fecha de vencimiento del credito. Obligatoria en compras a credito.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.SUBTOTAL_FACO      IS 'Suma de las lineas antes de descuento e impuesto.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.DESCUENTO_FACO     IS 'Total de descuentos.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.IMPUESTO_FACO      IS 'Total de impuestos.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.TOTAL_FACO         IS 'Columna virtual: subtotal menos descuento mas impuesto.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.OBSERVACION_FACO   IS 'Observaciones.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.ESTADO_FACO        IS 'Estado del registro: A=Activa, N=Anulada.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.USUARIO_CREA_FACO  IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.FECHA_CREA_FACO    IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.USUARIO_MOD_FACO   IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN COM_FACTURA_COMPRA.FECHA_MOD_FACO     IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: COM_FACTURA_COMPRA_DET
CREATE TABLE COM_FACTURA_COMPRA_DET (
    ID_FACTURA_COMPRA_DET  NUMBER(12)    DEFAULT SEQ_COM_FACTURA_COMPRA_DET.NEXTVAL NOT NULL,
    ID_FACTURA_COMPRA      NUMBER(12)    NOT NULL,
    ID_PRODUCTO            NUMBER(10)    NOT NULL,
    ID_LOTE                NUMBER(12),
    LINEA_FCDE             NUMBER(4)     NOT NULL,
    CANTIDAD_FCDE          NUMBER(14,3)  NOT NULL,
    COSTO_UNITARIO_FCDE    NUMBER(14,4)  NOT NULL,
    PORC_DESCUENTO_FCDE    NUMBER(5,2)   DEFAULT 0 NOT NULL,
    PORC_IMPUESTO_FCDE     NUMBER(5,2)   DEFAULT 0 NOT NULL,
    SUBTOTAL_FCDE          NUMBER(14,2)  GENERATED ALWAYS AS (ROUND(CANTIDAD_FCDE * COSTO_UNITARIO_FCDE, 2)) VIRTUAL,
    MONTO_DESCUENTO_FCDE   NUMBER(14,2)  GENERATED ALWAYS AS (ROUND(CANTIDAD_FCDE * COSTO_UNITARIO_FCDE * PORC_DESCUENTO_FCDE / 100, 2)) VIRTUAL,
    MONTO_IMPUESTO_FCDE    NUMBER(14,2)  GENERATED ALWAYS AS (ROUND(CANTIDAD_FCDE * COSTO_UNITARIO_FCDE * (1 - PORC_DESCUENTO_FCDE / 100) * PORC_IMPUESTO_FCDE / 100, 2)) VIRTUAL,
    USUARIO_CREA_FCDE      VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_FCDE        TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_FCDE       VARCHAR2(30),
    FECHA_MOD_FCDE         TIMESTAMP,
    CONSTRAINT PK_FCDE PRIMARY KEY (ID_FACTURA_COMPRA_DET)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_FCDE_FACO FOREIGN KEY (ID_FACTURA_COMPRA)
        REFERENCES COM_FACTURA_COMPRA (ID_FACTURA_COMPRA),
    CONSTRAINT FK_FCDE_PROD FOREIGN KEY (ID_PRODUCTO)
        REFERENCES PRO_PRODUCTO (ID_PRODUCTO),
    CONSTRAINT FK_FCDE_LOTE FOREIGN KEY (ID_LOTE, ID_PRODUCTO)
        REFERENCES PRO_LOTE (ID_LOTE, ID_PRODUCTO),
    CONSTRAINT UK_FCDE_FACO_LINEA UNIQUE (ID_FACTURA_COMPRA, LINEA_FCDE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_FCDE_CANTIDAD CHECK (CANTIDAD_FCDE > 0),
    CONSTRAINT CK_FCDE_COSTO CHECK (COSTO_UNITARIO_FCDE >= 0),
    CONSTRAINT CK_FCDE_PORC_DESC CHECK (PORC_DESCUENTO_FCDE BETWEEN 0 AND 100),
    CONSTRAINT CK_FCDE_PORC_IMPU CHECK (PORC_IMPUESTO_FCDE BETWEEN 0 AND 100),
    CONSTRAINT CK_FCDE_LINEA CHECK (LINEA_FCDE > 0)
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  COM_FACTURA_COMPRA_DET                        IS 'Detalle de productos comprados en una factura de compra. Los montos de linea son columnas virtuales.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.ID_FACTURA_COMPRA_DET  IS 'Identificador unico de la linea.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.ID_FACTURA_COMPRA      IS 'Factura a la que pertenece. FK a COM_FACTURA_COMPRA.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.ID_PRODUCTO            IS 'Producto comprado. FK a PRO_PRODUCTO.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.ID_LOTE                IS 'Lote recibido. FK compuesta a PRO_LOTE junto con ID_PRODUCTO.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.LINEA_FCDE             IS 'Numero de linea dentro de la factura.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.CANTIDAD_FCDE          IS 'Cantidad comprada.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.COSTO_UNITARIO_FCDE    IS 'Costo unitario pactado en la factura.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.PORC_DESCUENTO_FCDE    IS 'Porcentaje de descuento de la linea.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.PORC_IMPUESTO_FCDE     IS 'Porcentaje de impuesto aplicado a la linea. Cero si es exenta.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.SUBTOTAL_FCDE          IS 'Columna virtual: cantidad por costo unitario.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.MONTO_DESCUENTO_FCDE   IS 'Columna virtual: monto de descuento de la linea.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.MONTO_IMPUESTO_FCDE    IS 'Columna virtual: monto de impuesto de la linea, calculado sobre el neto de descuento.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.USUARIO_CREA_FCDE      IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.FECHA_CREA_FCDE        IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.USUARIO_MOD_FCDE       IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN COM_FACTURA_COMPRA_DET.FECHA_MOD_FCDE         IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: COM_ABONO_PAGAR
CREATE TABLE COM_ABONO_PAGAR (
    ID_ABONO_PAGAR        NUMBER(12)     DEFAULT SEQ_COM_ABONO_PAGAR.NEXTVAL NOT NULL,
    ID_FACTURA_COMPRA     NUMBER(12)     NOT NULL,
    ID_USUARIO            NUMBER(10)     NOT NULL,
    NUM_COMPROBANTE_ABPA  VARCHAR2(30)   NOT NULL,
    FECHA_ABPA            DATE           DEFAULT SYSDATE NOT NULL,
    MONTO_ABPA            NUMBER(14,2)   NOT NULL,
    OBSERVACION_ABPA      VARCHAR2(200),
    ESTADO_ABPA           VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_ABPA     VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_ABPA       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_ABPA      VARCHAR2(30),
    FECHA_MOD_ABPA        TIMESTAMP,
    CONSTRAINT PK_ABPA PRIMARY KEY (ID_ABONO_PAGAR)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_ABPA_FACO FOREIGN KEY (ID_FACTURA_COMPRA)
        REFERENCES COM_FACTURA_COMPRA (ID_FACTURA_COMPRA),
    CONSTRAINT FK_ABPA_USU FOREIGN KEY (ID_USUARIO)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT UK_ABPA_COMPROBANTE UNIQUE (NUM_COMPROBANTE_ABPA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_ABPA_MONTO CHECK (MONTO_ABPA > 0),
    CONSTRAINT CK_ABPA_ESTADO CHECK (ESTADO_ABPA IN ('A','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  COM_ABONO_PAGAR                       IS 'Abonos (pagos parciales) a facturas de compra a credito. El saldo de la cuenta por pagar se calcula a partir de estos abonos.';
COMMENT ON COLUMN COM_ABONO_PAGAR.ID_ABONO_PAGAR        IS 'Identificador unico del abono.';
COMMENT ON COLUMN COM_ABONO_PAGAR.ID_FACTURA_COMPRA     IS 'Factura de compra que se abona. FK a COM_FACTURA_COMPRA.';
COMMENT ON COLUMN COM_ABONO_PAGAR.ID_USUARIO            IS 'Usuario que registro el abono. FK a SEG_USUARIO.';
COMMENT ON COLUMN COM_ABONO_PAGAR.NUM_COMPROBANTE_ABPA  IS 'Numero de comprobante del pago.';
COMMENT ON COLUMN COM_ABONO_PAGAR.FECHA_ABPA            IS 'Fecha del abono.';
COMMENT ON COLUMN COM_ABONO_PAGAR.MONTO_ABPA            IS 'Monto abonado.';
COMMENT ON COLUMN COM_ABONO_PAGAR.OBSERVACION_ABPA      IS 'Observaciones.';
COMMENT ON COLUMN COM_ABONO_PAGAR.ESTADO_ABPA           IS 'Estado del registro: A=Activo, N=Anulado.';
COMMENT ON COLUMN COM_ABONO_PAGAR.USUARIO_CREA_ABPA     IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN COM_ABONO_PAGAR.FECHA_CREA_ABPA       IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN COM_ABONO_PAGAR.USUARIO_MOD_ABPA      IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN COM_ABONO_PAGAR.FECHA_MOD_ABPA        IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: COM_DEVOLUCION
CREATE TABLE COM_DEVOLUCION (
    ID_DEVOLUCION_COMPRA  NUMBER(12)     DEFAULT SEQ_COM_DEVOLUCION.NEXTVAL NOT NULL,
    ID_FACTURA_COMPRA     NUMBER(12)     NOT NULL,
    ID_BODEGA             NUMBER(10)     NOT NULL,
    ID_USUARIO            NUMBER(10)     NOT NULL,
    CONSECUTIVO_DEVC      VARCHAR2(20)   NOT NULL,
    FECHA_DEVC            DATE           DEFAULT SYSDATE NOT NULL,
    MOTIVO_DEVC           VARCHAR2(250)  NOT NULL,
    ESTADO_DEVC           VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_DEVC     VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_DEVC       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_DEVC      VARCHAR2(30),
    FECHA_MOD_DEVC        TIMESTAMP,
    CONSTRAINT PK_DEVC PRIMARY KEY (ID_DEVOLUCION_COMPRA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_DEVC_FACO FOREIGN KEY (ID_FACTURA_COMPRA)
        REFERENCES COM_FACTURA_COMPRA (ID_FACTURA_COMPRA),
    CONSTRAINT FK_DEVC_BODE FOREIGN KEY (ID_BODEGA)
        REFERENCES INV_BODEGA (ID_BODEGA),
    CONSTRAINT FK_DEVC_USU FOREIGN KEY (ID_USUARIO)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT UK_DEVC_CONSECUTIVO UNIQUE (CONSECUTIVO_DEVC)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_DEVC_ESTADO CHECK (ESTADO_DEVC IN ('A','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  COM_DEVOLUCION                       IS 'Encabezado de las devoluciones de producto a un proveedor, total o parcial, sobre una factura de compra.';
COMMENT ON COLUMN COM_DEVOLUCION.ID_DEVOLUCION_COMPRA  IS 'Identificador unico de la devolucion de compra.';
COMMENT ON COLUMN COM_DEVOLUCION.ID_FACTURA_COMPRA     IS 'Factura de compra que se devuelve. FK a COM_FACTURA_COMPRA.';
COMMENT ON COLUMN COM_DEVOLUCION.ID_BODEGA             IS 'Bodega de donde sale el producto devuelto. FK a INV_BODEGA.';
COMMENT ON COLUMN COM_DEVOLUCION.ID_USUARIO            IS 'Usuario que registro la devolucion. FK a SEG_USUARIO.';
COMMENT ON COLUMN COM_DEVOLUCION.CONSECUTIVO_DEVC      IS 'Consecutivo interno de la devolucion.';
COMMENT ON COLUMN COM_DEVOLUCION.FECHA_DEVC            IS 'Fecha de la devolucion.';
COMMENT ON COLUMN COM_DEVOLUCION.MOTIVO_DEVC           IS 'Motivo de la devolucion.';
COMMENT ON COLUMN COM_DEVOLUCION.ESTADO_DEVC           IS 'Estado del registro: A=Activo, N=Anulado.';
COMMENT ON COLUMN COM_DEVOLUCION.USUARIO_CREA_DEVC     IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN COM_DEVOLUCION.FECHA_CREA_DEVC       IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN COM_DEVOLUCION.USUARIO_MOD_DEVC      IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN COM_DEVOLUCION.FECHA_MOD_DEVC        IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: COM_DEVOLUCION_DET
CREATE TABLE COM_DEVOLUCION_DET (
    ID_DEVOLUCION_COMPRA_DET  NUMBER(12)     DEFAULT SEQ_COM_DEVOLUCION_DET.NEXTVAL NOT NULL,
    ID_DEVOLUCION_COMPRA      NUMBER(12)     NOT NULL,
    ID_FACTURA_COMPRA_DET     NUMBER(12)     NOT NULL,
    CANTIDAD_DVCD             NUMBER(14,3)   NOT NULL,
    MOTIVO_DVCD               VARCHAR2(200),
    USUARIO_CREA_DVCD         VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_DVCD           TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_DVCD          VARCHAR2(30),
    FECHA_MOD_DVCD            TIMESTAMP,
    CONSTRAINT PK_DVCD PRIMARY KEY (ID_DEVOLUCION_COMPRA_DET)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_DVCD_DEVC FOREIGN KEY (ID_DEVOLUCION_COMPRA)
        REFERENCES COM_DEVOLUCION (ID_DEVOLUCION_COMPRA),
    CONSTRAINT FK_DVCD_FCDE FOREIGN KEY (ID_FACTURA_COMPRA_DET)
        REFERENCES COM_FACTURA_COMPRA_DET (ID_FACTURA_COMPRA_DET),
    CONSTRAINT UK_DVCD_DEVC_FCDE UNIQUE (ID_DEVOLUCION_COMPRA, ID_FACTURA_COMPRA_DET)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_DVCD_CANTIDAD CHECK (CANTIDAD_DVCD > 0)
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  COM_DEVOLUCION_DET                           IS 'Lineas de factura de compra devueltas y su cantidad. Producto, lote y costo se obtienen de la linea original; no se repiten aqui.';
COMMENT ON COLUMN COM_DEVOLUCION_DET.ID_DEVOLUCION_COMPRA_DET  IS 'Identificador unico de la linea devuelta.';
COMMENT ON COLUMN COM_DEVOLUCION_DET.ID_DEVOLUCION_COMPRA      IS 'Devolucion a la que pertenece. FK a COM_DEVOLUCION.';
COMMENT ON COLUMN COM_DEVOLUCION_DET.ID_FACTURA_COMPRA_DET     IS 'Linea de la factura de compra que se devuelve. FK a COM_FACTURA_COMPRA_DET.';
COMMENT ON COLUMN COM_DEVOLUCION_DET.CANTIDAD_DVCD             IS 'Cantidad devuelta.';
COMMENT ON COLUMN COM_DEVOLUCION_DET.MOTIVO_DVCD               IS 'Motivo especifico de la linea.';
COMMENT ON COLUMN COM_DEVOLUCION_DET.USUARIO_CREA_DVCD         IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN COM_DEVOLUCION_DET.FECHA_CREA_DVCD           IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN COM_DEVOLUCION_DET.USUARIO_MOD_DVCD          IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN COM_DEVOLUCION_DET.FECHA_MOD_DVCD            IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: COM_NOTA_CREDITO
CREATE TABLE COM_NOTA_CREDITO (
    ID_NOTA_CREDITO_COMPRA  NUMBER(12)    DEFAULT SEQ_COM_NOTA_CREDITO.NEXTVAL NOT NULL,
    ID_DEVOLUCION_COMPRA    NUMBER(12)    NOT NULL,
    ID_USUARIO              NUMBER(10)    NOT NULL,
    NUM_NOTA_NCCO           VARCHAR2(30)  NOT NULL,
    FECHA_NCCO              DATE          DEFAULT SYSDATE NOT NULL,
    ESTADO_NCCO             VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_NCCO       VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_NCCO         TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_NCCO        VARCHAR2(30),
    FECHA_MOD_NCCO          TIMESTAMP,
    CONSTRAINT PK_NCCO PRIMARY KEY (ID_NOTA_CREDITO_COMPRA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_NCCO_DEVC FOREIGN KEY (ID_DEVOLUCION_COMPRA)
        REFERENCES COM_DEVOLUCION (ID_DEVOLUCION_COMPRA),
    CONSTRAINT FK_NCCO_USU FOREIGN KEY (ID_USUARIO)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT UK_NCCO_DEVC UNIQUE (ID_DEVOLUCION_COMPRA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_NCCO_ESTADO CHECK (ESTADO_NCCO IN ('A','C','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  COM_NOTA_CREDITO                         IS 'Notas de credito emitidas por el proveedor para pagar una devolucion de compra. Cada devolucion genera a lo sumo una nota.';
COMMENT ON COLUMN COM_NOTA_CREDITO.ID_NOTA_CREDITO_COMPRA  IS 'Identificador unico de la nota de credito de compra.';
COMMENT ON COLUMN COM_NOTA_CREDITO.ID_DEVOLUCION_COMPRA    IS 'Devolucion que origina la nota. FK a COM_DEVOLUCION. La factura y el proveedor se obtienen a traves de la devolucion.';
COMMENT ON COLUMN COM_NOTA_CREDITO.ID_USUARIO              IS 'Usuario que registro la nota. FK a SEG_USUARIO.';
COMMENT ON COLUMN COM_NOTA_CREDITO.NUM_NOTA_NCCO           IS 'Numero de la nota de credito del proveedor.';
COMMENT ON COLUMN COM_NOTA_CREDITO.FECHA_NCCO              IS 'Fecha de la nota de credito.';
COMMENT ON COLUMN COM_NOTA_CREDITO.ESTADO_NCCO             IS 'Estado del registro: A=Disponible, C=Aplicada, N=Anulada.';
COMMENT ON COLUMN COM_NOTA_CREDITO.USUARIO_CREA_NCCO       IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN COM_NOTA_CREDITO.FECHA_CREA_NCCO         IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN COM_NOTA_CREDITO.USUARIO_MOD_NCCO        IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN COM_NOTA_CREDITO.FECHA_MOD_NCCO          IS 'Fecha y hora de la ultima modificacion.';

-- VISTA: V_CUENTA_PAGAR
CREATE OR REPLACE VIEW V_CUENTA_PAGAR AS
SELECT f.ID_FACTURA_COMPRA,
       f.ID_PROVEEDOR,
       f.NUM_FACTURA_FACO,
       f.FECHA_FACO                                               AS FECHA_EMISION,
       f.FECHA_VENCIM_FACO                                        AS FECHA_VENCIMIENTO,
       f.TOTAL_FACO                                               AS MONTO_ORIGINAL,
       NVL(a.ABONADO, 0)                                          AS MONTO_ABONADO,
       f.TOTAL_FACO - NVL(a.ABONADO, 0)                           AS SALDO,
       a.ULTIMO_ABONO                                             AS FECHA_ULTIMO_ABONO,
       CASE WHEN f.TOTAL_FACO - NVL(a.ABONADO, 0) <= 0 THEN 'CANCELADA'
            WHEN NVL(a.ABONADO, 0) > 0                 THEN 'ABONADA'
            ELSE 'PENDIENTE' END                                  AS ESTADO
  FROM COM_FACTURA_COMPRA f
       LEFT JOIN (SELECT ID_FACTURA_COMPRA,
                         SUM(MONTO_ABPA) AS ABONADO,
                         MAX(FECHA_ABPA) AS ULTIMO_ABONO
                    FROM COM_ABONO_PAGAR
                   WHERE ESTADO_ABPA = 'A'
                   GROUP BY ID_FACTURA_COMPRA) a ON a.ID_FACTURA_COMPRA = f.ID_FACTURA_COMPRA
 WHERE f.ES_CREDITO_FACO = 'S'
   AND f.ESTADO_FACO = 'A';

COMMENT ON TABLE V_CUENTA_PAGAR IS 'Cuentas por pagar: facturas de compra a credito con su monto abonado y saldo. Monto original, saldo y estado se calculan; no se almacenan.';

-- VISTA: V_SALDO_PROVEEDOR
CREATE OR REPLACE VIEW V_SALDO_PROVEEDOR AS
SELECT pr.ID_PROVEEDOR,
       pr.CODIGO_PROVE,
       pj.RAZON_SOCIAL_PEJU                                       AS NOMBRE_PROVEEDOR,
       pr.LIMITE_CREDITO_PROVE                                    AS LIMITE_CREDITO,
       NVL(SUM(cxp.SALDO), 0)                                     AS SALDO_PENDIENTE,
       pr.LIMITE_CREDITO_PROVE - NVL(SUM(cxp.SALDO), 0)           AS CREDITO_DISPONIBLE,
       NVL(SUM(CASE WHEN cxp.FECHA_VENCIMIENTO < SYSDATE
                    THEN cxp.SALDO ELSE 0 END), 0)                AS SALDO_VENCIDO,
       COUNT(cxp.ID_FACTURA_COMPRA)                               AS DOCS_PENDIENTES
  FROM PER_PROVEEDOR pr
       JOIN PER_PERSONA_JURIDICA pj ON pj.ID_PERSONA_JURIDICA = pr.ID_PERSONA_JURIDICA
       LEFT JOIN V_CUENTA_PAGAR cxp ON cxp.ID_PROVEEDOR = pr.ID_PROVEEDOR
            AND cxp.SALDO > 0
 WHERE pr.ESTADO_PROVE = 'A'
 GROUP BY pr.ID_PROVEEDOR, pr.CODIGO_PROVE, pj.RAZON_SOCIAL_PEJU,
          pr.LIMITE_CREDITO_PROVE;

COMMENT ON TABLE V_SALDO_PROVEEDOR IS 'Saldo pendiente y credito disponible del negocio con cada proveedor, contra el limite de credito.';

PROMPT Modulo COM_ creado: 6 tablas, 6 secuencias, 2 vistas.


--------------------------------------------------------------------------------
-- SECCION 8 de 12: modulo VEN_
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Facturacion, pagos, cuentas por cobrar y devoluciones de clientes
--------------------------------------------------------------------------------
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SECUENCIAS DEL MODULO
CREATE SEQUENCE SEQ_VEN_FACTURA        START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_VEN_FACTURA_DET    START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_VEN_PAGO           START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_VEN_ABONO_COBRAR   START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_VEN_DEVOLUCION     START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_VEN_DEVOLUCION_DET  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_VEN_NOTA_CREDITO   START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- TABLA: VEN_FACTURA
CREATE TABLE VEN_FACTURA (
    ID_FACTURA_VENTA   NUMBER(12)     DEFAULT SEQ_VEN_FACTURA.NEXTVAL NOT NULL,
    ID_CLIENTE         NUMBER(10)     NOT NULL,
    ID_SUCURSAL        NUMBER(10)     NOT NULL,
    ID_USUARIO         NUMBER(10)     NOT NULL,
    NUM_FACTURA_FAVE   VARCHAR2(30)   NOT NULL,
    FECHA_FAVE         DATE           DEFAULT SYSDATE NOT NULL,
    ES_CREDITO_FAVE    VARCHAR2(1)    DEFAULT 'N' NOT NULL,
    FECHA_VENCIM_FAVE  DATE,
    SUBTOTAL_FAVE      NUMBER(14,2)   DEFAULT 0 NOT NULL,
    DESCUENTO_FAVE     NUMBER(14,2)   DEFAULT 0 NOT NULL,
    IMPUESTO_FAVE      NUMBER(14,2)   DEFAULT 0 NOT NULL,
    TOTAL_FAVE         NUMBER(14,2)   GENERATED ALWAYS AS (SUBTOTAL_FAVE - DESCUENTO_FAVE + IMPUESTO_FAVE) VIRTUAL,
    OBSERVACION_FAVE   VARCHAR2(250),
    ESTADO_FAVE        VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_FAVE  VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_FAVE    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_FAVE   VARCHAR2(30),
    FECHA_MOD_FAVE     TIMESTAMP,
    CONSTRAINT PK_FAVE PRIMARY KEY (ID_FACTURA_VENTA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_FAVE_CLI FOREIGN KEY (ID_CLIENTE)
        REFERENCES PER_CLIENTE (ID_CLIENTE),
    CONSTRAINT FK_FAVE_SUC FOREIGN KEY (ID_SUCURSAL)
        REFERENCES SEG_SUCURSAL (ID_SUCURSAL),
    CONSTRAINT FK_FAVE_USU FOREIGN KEY (ID_USUARIO)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT UK_FAVE_SUC_NUM UNIQUE (ID_SUCURSAL, NUM_FACTURA_FAVE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_FAVE_SUBTOTAL CHECK (SUBTOTAL_FAVE >= 0),
    CONSTRAINT CK_FAVE_DESCUENTO CHECK (DESCUENTO_FAVE >= 0 AND DESCUENTO_FAVE <= SUBTOTAL_FAVE),
    CONSTRAINT CK_FAVE_IMPUESTO CHECK (IMPUESTO_FAVE >= 0),
    CONSTRAINT CK_FAVE_CRED_VENCIM CHECK (ES_CREDITO_FAVE = 'N' OR FECHA_VENCIM_FAVE IS NOT NULL),
    CONSTRAINT CK_FAVE_FECHAS CHECK (FECHA_VENCIM_FAVE IS NULL OR FECHA_VENCIM_FAVE >= FECHA_FAVE),
    CONSTRAINT CK_FAVE_CREDITO CHECK (ES_CREDITO_FAVE IN ('S','N')),
    CONSTRAINT CK_FAVE_ESTADO CHECK (ESTADO_FAVE IN ('A','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  VEN_FACTURA                    IS 'Facturas de venta. Siempre tienen cliente (el cliente por defecto si no hay uno registrado). Una factura a credito con saldo es una cuenta por cobrar (ver V_CUENTA_COBRAR).';
COMMENT ON COLUMN VEN_FACTURA.ID_FACTURA_VENTA   IS 'Identificador unico de la factura de venta.';
COMMENT ON COLUMN VEN_FACTURA.ID_CLIENTE         IS 'Cliente facturado. FK a PER_CLIENTE.';
COMMENT ON COLUMN VEN_FACTURA.ID_SUCURSAL        IS 'Sucursal que factura. FK a SEG_SUCURSAL.';
COMMENT ON COLUMN VEN_FACTURA.ID_USUARIO         IS 'Usuario (cajero) que emitio la factura. FK a SEG_USUARIO.';
COMMENT ON COLUMN VEN_FACTURA.NUM_FACTURA_FAVE   IS 'Numero de factura, unico dentro de la sucursal.';
COMMENT ON COLUMN VEN_FACTURA.FECHA_FAVE         IS 'Fecha y hora de la factura.';
COMMENT ON COLUMN VEN_FACTURA.ES_CREDITO_FAVE    IS 'Indica si la venta queda en cuentas por cobrar: S=Credito, N=Contado.';
COMMENT ON COLUMN VEN_FACTURA.FECHA_VENCIM_FAVE  IS 'Fecha de vencimiento del credito. Obligatoria en ventas a credito.';
COMMENT ON COLUMN VEN_FACTURA.SUBTOTAL_FAVE      IS 'Suma de las lineas antes de descuento e impuesto.';
COMMENT ON COLUMN VEN_FACTURA.DESCUENTO_FAVE     IS 'Total de descuentos.';
COMMENT ON COLUMN VEN_FACTURA.IMPUESTO_FAVE      IS 'Total de impuestos.';
COMMENT ON COLUMN VEN_FACTURA.TOTAL_FAVE         IS 'Columna virtual: subtotal menos descuento mas impuesto.';
COMMENT ON COLUMN VEN_FACTURA.OBSERVACION_FAVE   IS 'Observaciones.';
COMMENT ON COLUMN VEN_FACTURA.ESTADO_FAVE        IS 'Estado del registro: A=Activa, N=Anulada.';
COMMENT ON COLUMN VEN_FACTURA.USUARIO_CREA_FAVE  IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN VEN_FACTURA.FECHA_CREA_FAVE    IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN VEN_FACTURA.USUARIO_MOD_FAVE   IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN VEN_FACTURA.FECHA_MOD_FAVE     IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: VEN_FACTURA_DET
CREATE TABLE VEN_FACTURA_DET (
    ID_FACTURA_VENTA_DET  NUMBER(12)    DEFAULT SEQ_VEN_FACTURA_DET.NEXTVAL NOT NULL,
    ID_FACTURA_VENTA      NUMBER(12)    NOT NULL,
    ID_PRODUCTO           NUMBER(10),
    ID_SERVICIO           NUMBER(10),
    ID_LOTE               NUMBER(12),
    LINEA_FVDE            NUMBER(4)     NOT NULL,
    CANTIDAD_FVDE         NUMBER(14,3)  NOT NULL,
    PRECIO_UNITARIO_FVDE  NUMBER(14,4)  NOT NULL,
    PORC_DESCUENTO_FVDE   NUMBER(5,2)   DEFAULT 0 NOT NULL,
    PORC_IMPUESTO_FVDE    NUMBER(5,2)   DEFAULT 0 NOT NULL,
    SUBTOTAL_FVDE         NUMBER(14,2)  GENERATED ALWAYS AS (ROUND(CANTIDAD_FVDE * PRECIO_UNITARIO_FVDE, 2)) VIRTUAL,
    MONTO_DESCUENTO_FVDE  NUMBER(14,2)  GENERATED ALWAYS AS (ROUND(CANTIDAD_FVDE * PRECIO_UNITARIO_FVDE * PORC_DESCUENTO_FVDE / 100, 2)) VIRTUAL,
    MONTO_IMPUESTO_FVDE   NUMBER(14,2)  GENERATED ALWAYS AS (ROUND(CANTIDAD_FVDE * PRECIO_UNITARIO_FVDE * (1 - PORC_DESCUENTO_FVDE / 100) * PORC_IMPUESTO_FVDE / 100, 2)) VIRTUAL,
    USUARIO_CREA_FVDE     VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_FVDE       TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_FVDE      VARCHAR2(30),
    FECHA_MOD_FVDE        TIMESTAMP,
    CONSTRAINT PK_FVDE PRIMARY KEY (ID_FACTURA_VENTA_DET)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_FVDE_FAVE FOREIGN KEY (ID_FACTURA_VENTA)
        REFERENCES VEN_FACTURA (ID_FACTURA_VENTA),
    CONSTRAINT FK_FVDE_PROD FOREIGN KEY (ID_PRODUCTO)
        REFERENCES PRO_PRODUCTO (ID_PRODUCTO),
    CONSTRAINT FK_FVDE_SERV FOREIGN KEY (ID_SERVICIO)
        REFERENCES PRO_SERVICIO (ID_SERVICIO),
    CONSTRAINT FK_FVDE_LOTE FOREIGN KEY (ID_LOTE, ID_PRODUCTO)
        REFERENCES PRO_LOTE (ID_LOTE, ID_PRODUCTO),
    CONSTRAINT UK_FVDE_FAVE_LINEA UNIQUE (ID_FACTURA_VENTA, LINEA_FVDE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_FVDE_CANTIDAD CHECK (CANTIDAD_FVDE > 0),
    CONSTRAINT CK_FVDE_PRECIO CHECK (PRECIO_UNITARIO_FVDE >= 0),
    CONSTRAINT CK_FVDE_PORC_DESC CHECK (PORC_DESCUENTO_FVDE BETWEEN 0 AND 100),
    CONSTRAINT CK_FVDE_PORC_IMPU CHECK (PORC_IMPUESTO_FVDE BETWEEN 0 AND 100),
    CONSTRAINT CK_FVDE_LINEA CHECK (LINEA_FVDE > 0),
    CONSTRAINT CK_FVDE_PROD_SERV CHECK (
            (ID_PRODUCTO IS NOT NULL AND ID_SERVICIO IS NULL)
            OR (ID_PRODUCTO IS NULL AND ID_SERVICIO IS NOT NULL)
        ),
    CONSTRAINT CK_FVDE_LOTE_PROD CHECK (ID_LOTE IS NULL OR ID_PRODUCTO IS NOT NULL)
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  VEN_FACTURA_DET                       IS 'Detalle de la factura de venta: cada linea cobra un producto o un servicio, con su precio, descuento e impuesto. Los montos de linea son columnas virtuales.';
COMMENT ON COLUMN VEN_FACTURA_DET.ID_FACTURA_VENTA_DET  IS 'Identificador unico de la linea.';
COMMENT ON COLUMN VEN_FACTURA_DET.ID_FACTURA_VENTA      IS 'Factura a la que pertenece. FK a VEN_FACTURA.';
COMMENT ON COLUMN VEN_FACTURA_DET.ID_PRODUCTO           IS 'Producto vendido. FK a PRO_PRODUCTO. Excluyente con ID_SERVICIO.';
COMMENT ON COLUMN VEN_FACTURA_DET.ID_SERVICIO           IS 'Servicio vendido. FK a PRO_SERVICIO. Excluyente con ID_PRODUCTO.';
COMMENT ON COLUMN VEN_FACTURA_DET.ID_LOTE               IS 'Lote vendido. FK compuesta a PRO_LOTE junto con ID_PRODUCTO.';
COMMENT ON COLUMN VEN_FACTURA_DET.LINEA_FVDE            IS 'Numero de linea dentro de la factura.';
COMMENT ON COLUMN VEN_FACTURA_DET.CANTIDAD_FVDE         IS 'Cantidad vendida.';
COMMENT ON COLUMN VEN_FACTURA_DET.PRECIO_UNITARIO_FVDE  IS 'Precio unitario sin impuesto al momento de la venta.';
COMMENT ON COLUMN VEN_FACTURA_DET.PORC_DESCUENTO_FVDE   IS 'Porcentaje de descuento aplicado a la linea.';
COMMENT ON COLUMN VEN_FACTURA_DET.PORC_IMPUESTO_FVDE    IS 'Porcentaje de impuesto aplicado a la linea. Cero si es exenta.';
COMMENT ON COLUMN VEN_FACTURA_DET.SUBTOTAL_FVDE         IS 'Columna virtual: cantidad por precio unitario.';
COMMENT ON COLUMN VEN_FACTURA_DET.MONTO_DESCUENTO_FVDE  IS 'Columna virtual: monto de descuento de la linea.';
COMMENT ON COLUMN VEN_FACTURA_DET.MONTO_IMPUESTO_FVDE   IS 'Columna virtual: monto de impuesto de la linea, calculado sobre el neto de descuento.';
COMMENT ON COLUMN VEN_FACTURA_DET.USUARIO_CREA_FVDE     IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN VEN_FACTURA_DET.FECHA_CREA_FVDE       IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN VEN_FACTURA_DET.USUARIO_MOD_FVDE      IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN VEN_FACTURA_DET.FECHA_MOD_FVDE        IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: VEN_PAGO
CREATE TABLE VEN_PAGO (
    ID_PAGO            NUMBER(12)    DEFAULT SEQ_VEN_PAGO.NEXTVAL NOT NULL,
    ID_FACTURA_VENTA   NUMBER(12)    NOT NULL,
    TIPO_PAGO          VARCHAR2(15)  NOT NULL,
    LINEA_PAGO         NUMBER(4)     NOT NULL,
    MONTO_PAGO         NUMBER(14,2)  NOT NULL,
    MONTO_VUELTO_PAGO  NUMBER(14,2)  DEFAULT 0 NOT NULL,
    REFERENCIA_PAGO    VARCHAR2(50),
    FECHA_PAGO         TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    ESTADO_PAGO        VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_PAGO  VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_PAGO    TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PAGO   VARCHAR2(30),
    FECHA_MOD_PAGO     TIMESTAMP,
    CONSTRAINT PK_PAGO PRIMARY KEY (ID_PAGO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_PAGO_FAVE FOREIGN KEY (ID_FACTURA_VENTA)
        REFERENCES VEN_FACTURA (ID_FACTURA_VENTA),
    CONSTRAINT UK_PAGO_FAVE_LINEA UNIQUE (ID_FACTURA_VENTA, LINEA_PAGO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_PAGO_TIPO CHECK (TIPO_PAGO IN ('EFECTIVO','TARJETA','SINPE','TRANSFERENCIA','NOTA_CREDITO')),
    CONSTRAINT CK_PAGO_MONTO CHECK (MONTO_PAGO > 0),
    CONSTRAINT CK_PAGO_LINEA CHECK (LINEA_PAGO > 0),
    CONSTRAINT CK_PAGO_VUELTO CHECK (MONTO_VUELTO_PAGO >= 0 AND (MONTO_VUELTO_PAGO = 0 OR TIPO_PAGO = 'EFECTIVO')),
    CONSTRAINT CK_PAGO_REFERENCIA CHECK (TIPO_PAGO = 'EFECTIVO' OR REFERENCIA_PAGO IS NOT NULL),
    CONSTRAINT CK_PAGO_ESTADO CHECK (ESTADO_PAGO IN ('A','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  VEN_PAGO                    IS 'Pagos recibidos al cancelar una factura de venta. Una factura puede pagarse con varios tipos de pago.';
COMMENT ON COLUMN VEN_PAGO.ID_PAGO            IS 'Identificador unico del pago.';
COMMENT ON COLUMN VEN_PAGO.ID_FACTURA_VENTA   IS 'Factura que se paga. FK a VEN_FACTURA.';
COMMENT ON COLUMN VEN_PAGO.TIPO_PAGO          IS 'Tipo de pago: EFECTIVO, TARJETA, SINPE, TRANSFERENCIA o NOTA_CREDITO.';
COMMENT ON COLUMN VEN_PAGO.LINEA_PAGO         IS 'Numero de linea de pago dentro de la factura.';
COMMENT ON COLUMN VEN_PAGO.MONTO_PAGO         IS 'Monto recibido.';
COMMENT ON COLUMN VEN_PAGO.MONTO_VUELTO_PAGO  IS 'Vuelto entregado. Solo aplica a pagos en efectivo.';
COMMENT ON COLUMN VEN_PAGO.REFERENCIA_PAGO    IS 'Numero de autorizacion o referencia. Obligatorio en todo pago que no sea efectivo.';
COMMENT ON COLUMN VEN_PAGO.FECHA_PAGO         IS 'Fecha y hora del pago.';
COMMENT ON COLUMN VEN_PAGO.ESTADO_PAGO        IS 'Estado del registro: A=Activo, N=Anulado.';
COMMENT ON COLUMN VEN_PAGO.USUARIO_CREA_PAGO  IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN VEN_PAGO.FECHA_CREA_PAGO    IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN VEN_PAGO.USUARIO_MOD_PAGO   IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN VEN_PAGO.FECHA_MOD_PAGO     IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: VEN_ABONO_COBRAR
CREATE TABLE VEN_ABONO_COBRAR (
    ID_ABONO_COBRAR    NUMBER(12)    DEFAULT SEQ_VEN_ABONO_COBRAR.NEXTVAL NOT NULL,
    ID_FACTURA_VENTA   NUMBER(12)    NOT NULL,
    ID_USUARIO         NUMBER(10)    NOT NULL,
    TIPO_PAGO_ABCO     VARCHAR2(15)  NOT NULL,
    NUM_RECIBO_ABCO    VARCHAR2(30)  NOT NULL,
    FECHA_ABCO         DATE          DEFAULT SYSDATE NOT NULL,
    MONTO_ABCO         NUMBER(14,2)  NOT NULL,
    REFERENCIA_ABCO    VARCHAR2(50),
    ESTADO_ABCO        VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_ABCO  VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_ABCO    TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_ABCO   VARCHAR2(30),
    FECHA_MOD_ABCO     TIMESTAMP,
    CONSTRAINT PK_ABCO PRIMARY KEY (ID_ABONO_COBRAR)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_ABCO_FAVE FOREIGN KEY (ID_FACTURA_VENTA)
        REFERENCES VEN_FACTURA (ID_FACTURA_VENTA),
    CONSTRAINT FK_ABCO_USU FOREIGN KEY (ID_USUARIO)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT UK_ABCO_RECIBO UNIQUE (NUM_RECIBO_ABCO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_ABCO_TIPO CHECK (TIPO_PAGO_ABCO IN ('EFECTIVO','TARJETA','SINPE','TRANSFERENCIA','NOTA_CREDITO')),
    CONSTRAINT CK_ABCO_MONTO CHECK (MONTO_ABCO > 0),
    CONSTRAINT CK_ABCO_REFERENCIA CHECK (TIPO_PAGO_ABCO = 'EFECTIVO' OR REFERENCIA_ABCO IS NOT NULL),
    CONSTRAINT CK_ABCO_ESTADO CHECK (ESTADO_ABCO IN ('A','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  VEN_ABONO_COBRAR                    IS 'Abonos de clientes a facturas de venta a credito. El saldo de la cuenta por cobrar se calcula a partir de estos abonos.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.ID_ABONO_COBRAR    IS 'Identificador unico del abono.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.ID_FACTURA_VENTA   IS 'Factura de venta que se abona. FK a VEN_FACTURA.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.ID_USUARIO         IS 'Usuario que recibio el abono. FK a SEG_USUARIO.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.TIPO_PAGO_ABCO     IS 'Tipo de pago del abono: EFECTIVO, TARJETA, SINPE, TRANSFERENCIA o NOTA_CREDITO.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.NUM_RECIBO_ABCO    IS 'Numero de recibo entregado al cliente.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.FECHA_ABCO         IS 'Fecha del abono.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.MONTO_ABCO         IS 'Monto abonado.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.REFERENCIA_ABCO    IS 'Numero de autorizacion o referencia. Obligatorio en todo abono que no sea efectivo.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.ESTADO_ABCO        IS 'Estado del registro: A=Activo, N=Anulado.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.USUARIO_CREA_ABCO  IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.FECHA_CREA_ABCO    IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.USUARIO_MOD_ABCO   IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN VEN_ABONO_COBRAR.FECHA_MOD_ABCO     IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: VEN_DEVOLUCION
CREATE TABLE VEN_DEVOLUCION (
    ID_DEVOLUCION_VENTA  NUMBER(12)     DEFAULT SEQ_VEN_DEVOLUCION.NEXTVAL NOT NULL,
    ID_FACTURA_VENTA     NUMBER(12)     NOT NULL,
    ID_BODEGA            NUMBER(10)     NOT NULL,
    ID_USUARIO           NUMBER(10)     NOT NULL,
    CONSECUTIVO_DEVV     VARCHAR2(20)   NOT NULL,
    FECHA_DEVV           DATE           DEFAULT SYSDATE NOT NULL,
    MOTIVO_DEVV          VARCHAR2(250)  NOT NULL,
    ESTADO_DEVV          VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_DEVV    VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_DEVV      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_DEVV     VARCHAR2(30),
    FECHA_MOD_DEVV       TIMESTAMP,
    CONSTRAINT PK_DEVV PRIMARY KEY (ID_DEVOLUCION_VENTA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_DEVV_FAVE FOREIGN KEY (ID_FACTURA_VENTA)
        REFERENCES VEN_FACTURA (ID_FACTURA_VENTA),
    CONSTRAINT FK_DEVV_BODE FOREIGN KEY (ID_BODEGA)
        REFERENCES INV_BODEGA (ID_BODEGA),
    CONSTRAINT FK_DEVV_USU FOREIGN KEY (ID_USUARIO)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT UK_DEVV_CONSECUTIVO UNIQUE (CONSECUTIVO_DEVV)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_DEVV_ESTADO CHECK (ESTADO_DEVV IN ('A','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  VEN_DEVOLUCION                      IS 'Encabezado de las devoluciones de un cliente, total o parcial, sobre una factura de venta.';
COMMENT ON COLUMN VEN_DEVOLUCION.ID_DEVOLUCION_VENTA  IS 'Identificador unico de la devolucion de venta.';
COMMENT ON COLUMN VEN_DEVOLUCION.ID_FACTURA_VENTA     IS 'Factura de venta que se devuelve. FK a VEN_FACTURA.';
COMMENT ON COLUMN VEN_DEVOLUCION.ID_BODEGA            IS 'Bodega que recibe el producto devuelto. FK a INV_BODEGA.';
COMMENT ON COLUMN VEN_DEVOLUCION.ID_USUARIO           IS 'Usuario que registro la devolucion. FK a SEG_USUARIO.';
COMMENT ON COLUMN VEN_DEVOLUCION.CONSECUTIVO_DEVV     IS 'Consecutivo interno de la devolucion.';
COMMENT ON COLUMN VEN_DEVOLUCION.FECHA_DEVV           IS 'Fecha de la devolucion.';
COMMENT ON COLUMN VEN_DEVOLUCION.MOTIVO_DEVV          IS 'Motivo de la devolucion.';
COMMENT ON COLUMN VEN_DEVOLUCION.ESTADO_DEVV          IS 'Estado del registro: A=Activo, N=Anulado.';
COMMENT ON COLUMN VEN_DEVOLUCION.USUARIO_CREA_DEVV    IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN VEN_DEVOLUCION.FECHA_CREA_DEVV      IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN VEN_DEVOLUCION.USUARIO_MOD_DEVV     IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN VEN_DEVOLUCION.FECHA_MOD_DEVV       IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: VEN_DEVOLUCION_DET
CREATE TABLE VEN_DEVOLUCION_DET (
    ID_DEVOLUCION_VENTA_DET  NUMBER(12)     DEFAULT SEQ_VEN_DEVOLUCION_DET.NEXTVAL NOT NULL,
    ID_DEVOLUCION_VENTA      NUMBER(12)     NOT NULL,
    ID_FACTURA_VENTA_DET     NUMBER(12)     NOT NULL,
    CANTIDAD_DVVD            NUMBER(14,3)   NOT NULL,
    MOTIVO_DVVD              VARCHAR2(200),
    USUARIO_CREA_DVVD        VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_DVVD          TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_DVVD         VARCHAR2(30),
    FECHA_MOD_DVVD           TIMESTAMP,
    CONSTRAINT PK_DVVD PRIMARY KEY (ID_DEVOLUCION_VENTA_DET)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_DVVD_DEVV FOREIGN KEY (ID_DEVOLUCION_VENTA)
        REFERENCES VEN_DEVOLUCION (ID_DEVOLUCION_VENTA),
    CONSTRAINT FK_DVVD_FVDE FOREIGN KEY (ID_FACTURA_VENTA_DET)
        REFERENCES VEN_FACTURA_DET (ID_FACTURA_VENTA_DET),
    CONSTRAINT UK_DVVD_DEVV_FVDE UNIQUE (ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA_DET)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_DVVD_CANTIDAD CHECK (CANTIDAD_DVVD > 0)
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  VEN_DEVOLUCION_DET                          IS 'Lineas de factura de venta devueltas y su cantidad. Producto o servicio, lote y precio se obtienen de la linea original; no se repiten aqui.';
COMMENT ON COLUMN VEN_DEVOLUCION_DET.ID_DEVOLUCION_VENTA_DET  IS 'Identificador unico de la linea devuelta.';
COMMENT ON COLUMN VEN_DEVOLUCION_DET.ID_DEVOLUCION_VENTA      IS 'Devolucion a la que pertenece. FK a VEN_DEVOLUCION.';
COMMENT ON COLUMN VEN_DEVOLUCION_DET.ID_FACTURA_VENTA_DET     IS 'Linea de la factura de venta que se devuelve. FK a VEN_FACTURA_DET.';
COMMENT ON COLUMN VEN_DEVOLUCION_DET.CANTIDAD_DVVD            IS 'Cantidad devuelta.';
COMMENT ON COLUMN VEN_DEVOLUCION_DET.MOTIVO_DVVD              IS 'Motivo especifico de la linea.';
COMMENT ON COLUMN VEN_DEVOLUCION_DET.USUARIO_CREA_DVVD        IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN VEN_DEVOLUCION_DET.FECHA_CREA_DVVD          IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN VEN_DEVOLUCION_DET.USUARIO_MOD_DVVD         IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN VEN_DEVOLUCION_DET.FECHA_MOD_DVVD           IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: VEN_NOTA_CREDITO
CREATE TABLE VEN_NOTA_CREDITO (
    ID_NOTA_CREDITO_VENTA  NUMBER(12)    DEFAULT SEQ_VEN_NOTA_CREDITO.NEXTVAL NOT NULL,
    ID_DEVOLUCION_VENTA    NUMBER(12)    NOT NULL,
    ID_USUARIO             NUMBER(10)    NOT NULL,
    NUM_NOTA_NCVE          VARCHAR2(30)  NOT NULL,
    FECHA_NCVE             DATE          DEFAULT SYSDATE NOT NULL,
    ESTADO_NCVE            VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_NCVE      VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_NCVE        TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_NCVE       VARCHAR2(30),
    FECHA_MOD_NCVE         TIMESTAMP,
    CONSTRAINT PK_NCVE PRIMARY KEY (ID_NOTA_CREDITO_VENTA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_NCVE_DEVV FOREIGN KEY (ID_DEVOLUCION_VENTA)
        REFERENCES VEN_DEVOLUCION (ID_DEVOLUCION_VENTA),
    CONSTRAINT FK_NCVE_USU FOREIGN KEY (ID_USUARIO)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT UK_NCVE_DEVV UNIQUE (ID_DEVOLUCION_VENTA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT UK_NCVE_NUM UNIQUE (NUM_NOTA_NCVE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_NCVE_ESTADO CHECK (ESTADO_NCVE IN ('A','C','N'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  VEN_NOTA_CREDITO                        IS 'Notas de credito emitidas a clientes para pagar una devolucion de venta. Cada devolucion genera a lo sumo una nota.';
COMMENT ON COLUMN VEN_NOTA_CREDITO.ID_NOTA_CREDITO_VENTA  IS 'Identificador unico de la nota de credito de venta.';
COMMENT ON COLUMN VEN_NOTA_CREDITO.ID_DEVOLUCION_VENTA    IS 'Devolucion que origina la nota. FK a VEN_DEVOLUCION. La factura y el cliente se obtienen a traves de la devolucion.';
COMMENT ON COLUMN VEN_NOTA_CREDITO.ID_USUARIO             IS 'Usuario que emitio la nota. FK a SEG_USUARIO.';
COMMENT ON COLUMN VEN_NOTA_CREDITO.NUM_NOTA_NCVE          IS 'Numero de la nota de credito.';
COMMENT ON COLUMN VEN_NOTA_CREDITO.FECHA_NCVE             IS 'Fecha de la nota de credito.';
COMMENT ON COLUMN VEN_NOTA_CREDITO.ESTADO_NCVE            IS 'Estado del registro: A=Disponible, C=Aplicada, N=Anulada.';
COMMENT ON COLUMN VEN_NOTA_CREDITO.USUARIO_CREA_NCVE      IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN VEN_NOTA_CREDITO.FECHA_CREA_NCVE        IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN VEN_NOTA_CREDITO.USUARIO_MOD_NCVE       IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN VEN_NOTA_CREDITO.FECHA_MOD_NCVE         IS 'Fecha y hora de la ultima modificacion.';

-- VISTA: V_CUENTA_COBRAR
CREATE OR REPLACE VIEW V_CUENTA_COBRAR AS
SELECT f.ID_FACTURA_VENTA,
       f.ID_CLIENTE,
       f.ID_SUCURSAL,
       f.NUM_FACTURA_FAVE,
       f.FECHA_FAVE                                               AS FECHA_EMISION,
       f.FECHA_VENCIM_FAVE                                        AS FECHA_VENCIMIENTO,
       f.TOTAL_FAVE                                               AS MONTO_ORIGINAL,
       NVL(a.ABONADO, 0)                                          AS MONTO_ABONADO,
       f.TOTAL_FAVE - NVL(a.ABONADO, 0)                           AS SALDO,
       a.ULTIMO_ABONO                                             AS FECHA_ULTIMO_ABONO,
       CASE WHEN f.TOTAL_FAVE - NVL(a.ABONADO, 0) <= 0 THEN 'CANCELADA'
            WHEN NVL(a.ABONADO, 0) > 0                 THEN 'ABONADA'
            ELSE 'PENDIENTE' END                                  AS ESTADO
  FROM VEN_FACTURA f
       LEFT JOIN (SELECT ID_FACTURA_VENTA,
                         SUM(MONTO_ABCO) AS ABONADO,
                         MAX(FECHA_ABCO) AS ULTIMO_ABONO
                    FROM VEN_ABONO_COBRAR
                   WHERE ESTADO_ABCO = 'A'
                   GROUP BY ID_FACTURA_VENTA) a ON a.ID_FACTURA_VENTA = f.ID_FACTURA_VENTA
 WHERE f.ES_CREDITO_FAVE = 'S'
   AND f.ESTADO_FAVE = 'A';

COMMENT ON TABLE V_CUENTA_COBRAR IS 'Cuentas por cobrar: facturas de venta a credito con su monto abonado y saldo. Monto original, saldo y estado se calculan; no se almacenan.';

-- VISTA: V_SALDO_CLIENTE
CREATE OR REPLACE VIEW V_SALDO_CLIENTE AS
SELECT c.ID_CLIENTE,
       c.CODIGO_CLI,
       NVL(pj.RAZON_SOCIAL_PEJU,
           TRIM(pf.NOMBRE_PEFI || ' ' || pf.APELLIDO1_PEFI
                || ' ' || pf.APELLIDO2_PEFI))                     AS NOMBRE_CLIENTE,
       c.MONTO_MAX_CREDITO_CLI                                    AS LIMITE_CREDITO,
       NVL(SUM(cxc.SALDO), 0)                                     AS SALDO_PENDIENTE,
       c.MONTO_MAX_CREDITO_CLI - NVL(SUM(cxc.SALDO), 0)           AS CREDITO_DISPONIBLE,
       NVL(SUM(CASE WHEN cxc.FECHA_VENCIMIENTO < SYSDATE
                    THEN cxc.SALDO ELSE 0 END), 0)                AS SALDO_VENCIDO,
       COUNT(cxc.ID_FACTURA_VENTA)                                AS DOCS_PENDIENTES
  FROM PER_CLIENTE c
       LEFT JOIN PER_PERSONA_FISICA pf   ON pf.ID_PERSONA_FISICA   = c.ID_PERSONA
       LEFT JOIN PER_PERSONA_JURIDICA pj ON pj.ID_PERSONA_JURIDICA = c.ID_PERSONA
       LEFT JOIN V_CUENTA_COBRAR cxc     ON cxc.ID_CLIENTE = c.ID_CLIENTE
            AND cxc.SALDO > 0
 WHERE c.ESTADO_CLI = 'A'
 GROUP BY c.ID_CLIENTE, c.CODIGO_CLI, c.MONTO_MAX_CREDITO_CLI,
          pj.RAZON_SOCIAL_PEJU, pf.NOMBRE_PEFI, pf.APELLIDO1_PEFI, pf.APELLIDO2_PEFI;

COMMENT ON TABLE V_SALDO_CLIENTE IS 'Saldo pendiente y credito disponible de cada cliente, contra su monto maximo de credito.';

PROMPT Modulo VEN_ creado: 7 tablas, 7 secuencias, 2 vistas.


--------------------------------------------------------------------------------
-- SECCION 9 de 12: modulo PRM_
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Promociones, premios y descuentos
--------------------------------------------------------------------------------
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SECUENCIAS DEL MODULO
CREATE SEQUENCE SEQ_PRM_PROMOCION       START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRM_PATROCINADOR    START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRM_PREMIO          START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRM_ACCION_CLIENTE  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRM_DESCUENTO       START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRM_DESCUENTO_REGLA  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- TABLA: PRM_PROMOCION
CREATE TABLE PRM_PROMOCION (
    ID_PROMOCION       NUMBER(10)     DEFAULT SEQ_PRM_PROMOCION.NEXTVAL NOT NULL,
    ID_SUCURSAL        NUMBER(10),
    CODIGO_PROM        VARCHAR2(20)   NOT NULL,
    NOMBRE_PROM        VARCHAR2(100)  NOT NULL,
    DESCRIPCION_PROM   VARCHAR2(250),
    FECHA_INICIO_PROM  DATE           NOT NULL,
    FECHA_FIN_PROM     DATE           NOT NULL,
    ESTADO_PROM        VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_PROM  VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_PROM    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PROM   VARCHAR2(30),
    FECHA_MOD_PROM     TIMESTAMP,
    CONSTRAINT PK_PROM PRIMARY KEY (ID_PROMOCION)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_PROM_SUC FOREIGN KEY (ID_SUCURSAL)
        REFERENCES SEG_SUCURSAL (ID_SUCURSAL),
    CONSTRAINT UK_PROM_CODIGO UNIQUE (CODIGO_PROM)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_PROM_FECHAS CHECK (FECHA_FIN_PROM >= FECHA_INICIO_PROM),
    CONSTRAINT CK_PROM_ESTADO CHECK (ESTADO_PROM IN ('A','I','F'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRM_PROMOCION                    IS 'Promociones de mercadeo. Sus productos patrocinadores estan en PRM_PATROCINADOR y sus premios en PRM_PREMIO.';
COMMENT ON COLUMN PRM_PROMOCION.ID_PROMOCION       IS 'Identificador unico de la promocion.';
COMMENT ON COLUMN PRM_PROMOCION.ID_SUCURSAL        IS 'Sucursal donde aplica. FK a SEG_SUCURSAL. Nulo significa que aplica en toda la cadena.';
COMMENT ON COLUMN PRM_PROMOCION.CODIGO_PROM        IS 'Codigo interno de la promocion.';
COMMENT ON COLUMN PRM_PROMOCION.NOMBRE_PROM        IS 'Nombre de la promocion.';
COMMENT ON COLUMN PRM_PROMOCION.DESCRIPCION_PROM   IS 'Descripcion y condiciones.';
COMMENT ON COLUMN PRM_PROMOCION.FECHA_INICIO_PROM  IS 'Fecha de inicio de vigencia.';
COMMENT ON COLUMN PRM_PROMOCION.FECHA_FIN_PROM     IS 'Fecha de fin de vigencia.';
COMMENT ON COLUMN PRM_PROMOCION.ESTADO_PROM        IS 'Estado del registro: A=Activa, I=Inactiva, F=Finalizada.';
COMMENT ON COLUMN PRM_PROMOCION.USUARIO_CREA_PROM  IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRM_PROMOCION.FECHA_CREA_PROM    IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRM_PROMOCION.USUARIO_MOD_PROM   IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRM_PROMOCION.FECHA_MOD_PROM     IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PRM_PATROCINADOR
CREATE TABLE PRM_PATROCINADOR (
    ID_PATROCINADOR       NUMBER(10)    DEFAULT SEQ_PRM_PATROCINADOR.NEXTVAL NOT NULL,
    ID_PROMOCION          NUMBER(10)    NOT NULL,
    ID_PRODUCTO           NUMBER(10)    NOT NULL,
    CANT_REQUERIDA_PATR   NUMBER(14,3)  DEFAULT 1 NOT NULL,
    ACCIONES_OTORGA_PATR  NUMBER(10)    DEFAULT 1 NOT NULL,
    ESTADO_PATR           VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_PATR     VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_PATR       TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PATR      VARCHAR2(30),
    FECHA_MOD_PATR        TIMESTAMP,
    CONSTRAINT PK_PATR PRIMARY KEY (ID_PATROCINADOR)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_PATR_PROM FOREIGN KEY (ID_PROMOCION)
        REFERENCES PRM_PROMOCION (ID_PROMOCION),
    CONSTRAINT FK_PATR_PROD FOREIGN KEY (ID_PRODUCTO)
        REFERENCES PRO_PRODUCTO (ID_PRODUCTO),
    CONSTRAINT UK_PATR_PROM_PROD UNIQUE (ID_PROMOCION, ID_PRODUCTO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_PATR_CANTIDAD CHECK (CANT_REQUERIDA_PATR > 0),
    CONSTRAINT CK_PATR_ACCIONES CHECK (ACCIONES_OTORGA_PATR > 0),
    CONSTRAINT CK_PATR_ESTADO CHECK (ESTADO_PATR IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRM_PATROCINADOR                       IS 'Productos patrocinadores de una promocion: cuantas unidades hay que comprar y cuantas acciones se entregan al cumplirlo.';
COMMENT ON COLUMN PRM_PATROCINADOR.ID_PATROCINADOR       IS 'Identificador unico del producto patrocinador.';
COMMENT ON COLUMN PRM_PATROCINADOR.ID_PROMOCION          IS 'Promocion patrocinada. FK a PRM_PROMOCION.';
COMMENT ON COLUMN PRM_PATROCINADOR.ID_PRODUCTO           IS 'Producto patrocinador. FK a PRO_PRODUCTO.';
COMMENT ON COLUMN PRM_PATROCINADOR.CANT_REQUERIDA_PATR   IS 'Cantidad del producto necesaria para ser acreedor de acciones.';
COMMENT ON COLUMN PRM_PATROCINADOR.ACCIONES_OTORGA_PATR  IS 'Cantidad de acciones que se entregan al cumplir la cantidad requerida.';
COMMENT ON COLUMN PRM_PATROCINADOR.ESTADO_PATR           IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PRM_PATROCINADOR.USUARIO_CREA_PATR     IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRM_PATROCINADOR.FECHA_CREA_PATR       IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRM_PATROCINADOR.USUARIO_MOD_PATR      IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRM_PATROCINADOR.FECHA_MOD_PATR        IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PRM_PREMIO
CREATE TABLE PRM_PREMIO (
    ID_PREMIO             NUMBER(10)     DEFAULT SEQ_PRM_PREMIO.NEXTVAL NOT NULL,
    ID_PROMOCION          NUMBER(10)     NOT NULL,
    ID_PRODUCTO           NUMBER(10),
    NOMBRE_PREM           VARCHAR2(150)  NOT NULL,
    DESCRIPCION_PREM      VARCHAR2(250),
    ACCIONES_COSTO_PREM   NUMBER(10)     DEFAULT 1 NOT NULL,
    CANT_DISPONIBLE_PREM  NUMBER(10)     DEFAULT 0 NOT NULL,
    ESTADO_PREM           VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_PREM     VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_PREM       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_PREM      VARCHAR2(30),
    FECHA_MOD_PREM        TIMESTAMP,
    CONSTRAINT PK_PREM PRIMARY KEY (ID_PREMIO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_PREM_PROM FOREIGN KEY (ID_PROMOCION)
        REFERENCES PRM_PROMOCION (ID_PROMOCION),
    CONSTRAINT FK_PREM_PROD FOREIGN KEY (ID_PRODUCTO)
        REFERENCES PRO_PRODUCTO (ID_PRODUCTO),
    CONSTRAINT UK_PREM_PROM_NOMBRE UNIQUE (ID_PROMOCION, NOMBRE_PREM)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT UK_PREM_ID_PROM UNIQUE (ID_PREMIO, ID_PROMOCION)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_PREM_ACCIONES CHECK (ACCIONES_COSTO_PREM > 0),
    CONSTRAINT CK_PREM_DISPONIBLE CHECK (CANT_DISPONIBLE_PREM >= 0),
    CONSTRAINT CK_PREM_ESTADO CHECK (ESTADO_PREM IN ('A','I','G'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRM_PREMIO                       IS 'Premios que se pueden obtener en una promocion a cambio de acciones.';
COMMENT ON COLUMN PRM_PREMIO.ID_PREMIO             IS 'Identificador unico del premio.';
COMMENT ON COLUMN PRM_PREMIO.ID_PROMOCION          IS 'Promocion a la que pertenece el premio. FK a PRM_PROMOCION.';
COMMENT ON COLUMN PRM_PREMIO.ID_PRODUCTO           IS 'Producto del inventario que se entrega como premio. FK a PRO_PRODUCTO. Nulo si el premio no es un producto del inventario.';
COMMENT ON COLUMN PRM_PREMIO.NOMBRE_PREM           IS 'Nombre del premio.';
COMMENT ON COLUMN PRM_PREMIO.DESCRIPCION_PREM      IS 'Descripcion del premio.';
COMMENT ON COLUMN PRM_PREMIO.ACCIONES_COSTO_PREM   IS 'Cantidad de acciones necesarias para canjear el premio.';
COMMENT ON COLUMN PRM_PREMIO.CANT_DISPONIBLE_PREM  IS 'Unidades del premio disponibles para canje.';
COMMENT ON COLUMN PRM_PREMIO.ESTADO_PREM           IS 'Estado del registro: A=Activo, I=Inactivo, G=Agotado.';
COMMENT ON COLUMN PRM_PREMIO.USUARIO_CREA_PREM     IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRM_PREMIO.FECHA_CREA_PREM       IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRM_PREMIO.USUARIO_MOD_PREM      IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRM_PREMIO.FECHA_MOD_PREM        IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PRM_ACCION_CLIENTE
CREATE TABLE PRM_ACCION_CLIENTE (
    ID_ACCION_CLIENTE   NUMBER(12)    DEFAULT SEQ_PRM_ACCION_CLIENTE.NEXTVAL NOT NULL,
    ID_PROMOCION        NUMBER(10)    NOT NULL,
    ID_FACTURA_VENTA    NUMBER(12)    NOT NULL,
    ID_PREMIO           NUMBER(10),
    CANT_ACCIONES_ACLI  NUMBER(10)    NOT NULL,
    FECHA_CANJE_ACLI    DATE,
    ESTADO_ACLI         VARCHAR2(1)   GENERATED ALWAYS AS (CASE WHEN ID_PREMIO IS NULL THEN 'D' ELSE 'C' END) VIRTUAL,
    USUARIO_CREA_ACLI   VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_ACLI     TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_ACLI    VARCHAR2(30),
    FECHA_MOD_ACLI      TIMESTAMP,
    CONSTRAINT PK_ACLI PRIMARY KEY (ID_ACCION_CLIENTE)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_ACLI_PROM FOREIGN KEY (ID_PROMOCION)
        REFERENCES PRM_PROMOCION (ID_PROMOCION),
    CONSTRAINT FK_ACLI_FAVE FOREIGN KEY (ID_FACTURA_VENTA)
        REFERENCES VEN_FACTURA (ID_FACTURA_VENTA),
    CONSTRAINT FK_ACLI_PREM FOREIGN KEY (ID_PREMIO, ID_PROMOCION)
        REFERENCES PRM_PREMIO (ID_PREMIO, ID_PROMOCION),
    CONSTRAINT UK_ACLI_PROM_FAVE UNIQUE (ID_PROMOCION, ID_FACTURA_VENTA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_ACLI_CANTIDAD CHECK (CANT_ACCIONES_ACLI > 0),
    CONSTRAINT CK_ACLI_CANJE CHECK (
            (ID_PREMIO IS NULL AND FECHA_CANJE_ACLI IS NULL)
            OR (ID_PREMIO IS NOT NULL AND FECHA_CANJE_ACLI IS NOT NULL)
        )
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRM_ACCION_CLIENTE                     IS 'Acciones que una factura de venta le otorga a su cliente dentro de una promocion, y el premio canjeado con ellas si lo hay. El cliente y la fecha se obtienen de la factura.';
COMMENT ON COLUMN PRM_ACCION_CLIENTE.ID_ACCION_CLIENTE   IS 'Identificador unico del registro de acciones.';
COMMENT ON COLUMN PRM_ACCION_CLIENTE.ID_PROMOCION        IS 'Promocion que otorga las acciones. FK a PRM_PROMOCION.';
COMMENT ON COLUMN PRM_ACCION_CLIENTE.ID_FACTURA_VENTA    IS 'Factura de venta que genero las acciones. FK a VEN_FACTURA.';
COMMENT ON COLUMN PRM_ACCION_CLIENTE.ID_PREMIO           IS 'Premio canjeado. FK compuesta a PRM_PREMIO junto con ID_PROMOCION, lo que garantiza que el premio sea de la misma promocion.';
COMMENT ON COLUMN PRM_ACCION_CLIENTE.CANT_ACCIONES_ACLI  IS 'Cantidad de acciones otorgadas.';
COMMENT ON COLUMN PRM_ACCION_CLIENTE.FECHA_CANJE_ACLI    IS 'Fecha en que se canjeo el premio. Nulo mientras las acciones esten disponibles.';
COMMENT ON COLUMN PRM_ACCION_CLIENTE.ESTADO_ACLI         IS 'Columna virtual: C=Canjeada si ya tiene premio, D=Disponible en caso contrario.';
COMMENT ON COLUMN PRM_ACCION_CLIENTE.USUARIO_CREA_ACLI   IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRM_ACCION_CLIENTE.FECHA_CREA_ACLI     IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRM_ACCION_CLIENTE.USUARIO_MOD_ACLI    IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRM_ACCION_CLIENTE.FECHA_MOD_ACLI      IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PRM_DESCUENTO
CREATE TABLE PRM_DESCUENTO (
    ID_DESCUENTO        NUMBER(10)     DEFAULT SEQ_PRM_DESCUENTO.NEXTVAL NOT NULL,
    ID_SUCURSAL         NUMBER(10),
    CODIGO_DSCT         VARCHAR2(20)   NOT NULL,
    NOMBRE_DSCT         VARCHAR2(100)  NOT NULL,
    PORCENTAJE_DSCT     NUMBER(5,2)    DEFAULT 0 NOT NULL,
    MONTO_FIJO_DSCT     NUMBER(14,2)   DEFAULT 0 NOT NULL,
    FECHA_INICIO_DSCT   DATE           NOT NULL,
    FECHA_FIN_DSCT      DATE           NOT NULL,
    PRIORIDAD_DSCT      NUMBER(3)      DEFAULT 1 NOT NULL,
    ES_ACUMULABLE_DSCT  VARCHAR2(1)    DEFAULT 'N' NOT NULL,
    ESTADO_DSCT         VARCHAR2(1)    DEFAULT 'A' NOT NULL,
    USUARIO_CREA_DSCT   VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_DSCT     TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_DSCT    VARCHAR2(30),
    FECHA_MOD_DSCT      TIMESTAMP,
    CONSTRAINT PK_DSCT PRIMARY KEY (ID_DESCUENTO)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_DSCT_SUC FOREIGN KEY (ID_SUCURSAL)
        REFERENCES SEG_SUCURSAL (ID_SUCURSAL),
    CONSTRAINT UK_DSCT_CODIGO UNIQUE (CODIGO_DSCT)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT CK_DSCT_PRIORIDAD CHECK (PRIORIDAD_DSCT > 0),
    CONSTRAINT CK_DSCT_FECHAS CHECK (FECHA_FIN_DSCT >= FECHA_INICIO_DSCT),
    CONSTRAINT CK_DSCT_TIPO CHECK (
            (PORCENTAJE_DSCT > 0 AND PORCENTAJE_DSCT <= 100 AND MONTO_FIJO_DSCT = 0)
            OR (PORCENTAJE_DSCT = 0 AND MONTO_FIJO_DSCT > 0)
        ),
    CONSTRAINT CK_DSCT_ACUMULABLE CHECK (ES_ACUMULABLE_DSCT IN ('S','N')),
    CONSTRAINT CK_DSCT_ESTADO CHECK (ESTADO_DSCT IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRM_DESCUENTO                     IS 'Descuentos comerciales con su vigencia. A que productos aplica cada uno se define en PRM_DESCUENTO_REGLA.';
COMMENT ON COLUMN PRM_DESCUENTO.ID_DESCUENTO        IS 'Identificador unico del descuento.';
COMMENT ON COLUMN PRM_DESCUENTO.ID_SUCURSAL         IS 'Sucursal donde aplica. FK a SEG_SUCURSAL. Nulo significa que aplica en toda la cadena.';
COMMENT ON COLUMN PRM_DESCUENTO.CODIGO_DSCT         IS 'Codigo interno del descuento.';
COMMENT ON COLUMN PRM_DESCUENTO.NOMBRE_DSCT         IS 'Nombre del descuento.';
COMMENT ON COLUMN PRM_DESCUENTO.PORCENTAJE_DSCT     IS 'Porcentaje de descuento. Excluyente con el monto fijo.';
COMMENT ON COLUMN PRM_DESCUENTO.MONTO_FIJO_DSCT     IS 'Monto fijo de descuento. Excluyente con el porcentaje.';
COMMENT ON COLUMN PRM_DESCUENTO.FECHA_INICIO_DSCT   IS 'Fecha de inicio de vigencia.';
COMMENT ON COLUMN PRM_DESCUENTO.FECHA_FIN_DSCT      IS 'Fecha de fin de vigencia.';
COMMENT ON COLUMN PRM_DESCUENTO.PRIORIDAD_DSCT      IS 'Prioridad de aplicacion; 1 es la mas alta.';
COMMENT ON COLUMN PRM_DESCUENTO.ES_ACUMULABLE_DSCT  IS 'Indica si se puede acumular con otros descuentos: S=Si, N=No.';
COMMENT ON COLUMN PRM_DESCUENTO.ESTADO_DSCT         IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PRM_DESCUENTO.USUARIO_CREA_DSCT   IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRM_DESCUENTO.FECHA_CREA_DSCT     IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRM_DESCUENTO.USUARIO_MOD_DSCT    IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRM_DESCUENTO.FECHA_MOD_DSCT      IS 'Fecha y hora de la ultima modificacion.';

-- TABLA: PRM_DESCUENTO_REGLA
CREATE TABLE PRM_DESCUENTO_REGLA (
    ID_DESCUENTO_REGLA   NUMBER(10)    DEFAULT SEQ_PRM_DESCUENTO_REGLA.NEXTVAL NOT NULL,
    ID_DESCUENTO         NUMBER(10)    NOT NULL,
    ID_FAMILIA_PRODUCTO  NUMBER(10),
    ID_PROVEEDOR         NUMBER(10),
    DIAS_INGRESO_DSRE    NUMBER(5),
    DIAS_VENCIM_DSRE     NUMBER(5),
    TIPO_REGLA_DSRE      VARCHAR2(17)  GENERATED ALWAYS AS (CASE WHEN ID_FAMILIA_PRODUCTO IS NOT NULL THEN 'FAMILIA' WHEN ID_PROVEEDOR IS NOT NULL THEN 'PROVEEDOR' WHEN DIAS_INGRESO_DSRE IS NOT NULL THEN 'FECHA_INGRESO' ELSE 'FECHA_VENCIMIENTO' END) VIRTUAL,
    ESTADO_DSRE          VARCHAR2(1)   DEFAULT 'A' NOT NULL,
    USUARIO_CREA_DSRE    VARCHAR2(30)  DEFAULT USER NOT NULL,
    FECHA_CREA_DSRE      TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_MOD_DSRE     VARCHAR2(30),
    FECHA_MOD_DSRE       TIMESTAMP,
    CONSTRAINT PK_DSRE PRIMARY KEY (ID_DESCUENTO_REGLA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_DSRE_DSCT FOREIGN KEY (ID_DESCUENTO)
        REFERENCES PRM_DESCUENTO (ID_DESCUENTO),
    CONSTRAINT FK_DSRE_FAMI FOREIGN KEY (ID_FAMILIA_PRODUCTO)
        REFERENCES PRO_FAMILIA_PRODUCTO (ID_FAMILIA_PRODUCTO),
    CONSTRAINT FK_DSRE_PROVE FOREIGN KEY (ID_PROVEEDOR)
        REFERENCES PER_PROVEEDOR (ID_PROVEEDOR),
    CONSTRAINT CK_DSRE_DIAS_ING CHECK (DIAS_INGRESO_DSRE > 0),
    CONSTRAINT CK_DSRE_DIAS_VEN CHECK (DIAS_VENCIM_DSRE > 0),
    CONSTRAINT CK_DSRE_UN_CRITERIO CHECK (
            NVL2(ID_FAMILIA_PRODUCTO, 1, 0) + NVL2(ID_PROVEEDOR, 1, 0)
            + NVL2(DIAS_INGRESO_DSRE, 1, 0) + NVL2(DIAS_VENCIM_DSRE, 1, 0) = 1
        ),
    CONSTRAINT CK_DSRE_ESTADO CHECK (ESTADO_DSRE IN ('A','I'))
) TABLESPACE TBS_DATOS;

COMMENT ON TABLE  PRM_DESCUENTO_REGLA                      IS 'Criterio de aplicacion de un descuento: por familia, por proveedor, por dias desde el ingreso o por dias para el vencimiento. Cada regla usa exactamente un criterio.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.ID_DESCUENTO_REGLA   IS 'Identificador unico de la regla.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.ID_DESCUENTO         IS 'Descuento al que pertenece la regla. FK a PRM_DESCUENTO.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.ID_FAMILIA_PRODUCTO  IS 'Familia a la que aplica. FK a PRO_FAMILIA_PRODUCTO.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.ID_PROVEEDOR         IS 'Proveedor a cuyos productos aplica. FK a PER_PROVEEDOR.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.DIAS_INGRESO_DSRE    IS 'Aplica a lotes con al menos esta cantidad de dias desde su fecha de ingreso.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.DIAS_VENCIM_DSRE     IS 'Aplica a lotes a los que les faltan como maximo estos dias para vencer.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.TIPO_REGLA_DSRE      IS 'Columna virtual: FAMILIA, PROVEEDOR, FECHA_INGRESO o FECHA_VENCIMIENTO, segun el criterio que tiene valor.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.ESTADO_DSRE          IS 'Estado del registro: A=Activo, I=Inactivo.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.USUARIO_CREA_DSRE    IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.FECHA_CREA_DSRE      IS 'Fecha y hora de creacion del registro.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.USUARIO_MOD_DSRE     IS 'Usuario de base de datos que realizo la ultima modificacion.';
COMMENT ON COLUMN PRM_DESCUENTO_REGLA.FECHA_MOD_DSRE       IS 'Fecha y hora de la ultima modificacion.';

PROMPT Modulo PRM_ creado: 6 tablas, 6 secuencias.


--------------------------------------------------------------------------------
-- SECCION 10 de 12: modulo AUD_
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Bitacora de auditoria
--------------------------------------------------------------------------------
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SECUENCIAS DEL MODULO
CREATE SEQUENCE SEQ_AUD_BITACORA  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- TABLA: AUD_BITACORA
CREATE TABLE AUD_BITACORA (
    ID_BITACORA          NUMBER(12)     DEFAULT SEQ_AUD_BITACORA.NEXTVAL NOT NULL,
    ID_USUARIO           NUMBER(10),
    ID_SUCURSAL          NUMBER(10),
    TABLA_BITA           VARCHAR2(30)   NOT NULL,
    LLAVE_REGISTRO_BITA  VARCHAR2(50),
    OPERACION_BITA       VARCHAR2(10)   NOT NULL,
    MODULO_BITA          VARCHAR2(50),
    DESCRIPCION_BITA     VARCHAR2(500),
    DIRECCION_IP_BITA    VARCHAR2(45),
    FECHA_BITA           TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    USUARIO_CREA_BITA    VARCHAR2(30)   DEFAULT USER NOT NULL,
    FECHA_CREA_BITA      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT PK_BITA PRIMARY KEY (ID_BITACORA)
        USING INDEX TABLESPACE TBS_INDICES,
    CONSTRAINT FK_BITA_USU FOREIGN KEY (ID_USUARIO)
        REFERENCES SEG_USUARIO (ID_USUARIO),
    CONSTRAINT FK_BITA_SUC FOREIGN KEY (ID_SUCURSAL)
        REFERENCES SEG_SUCURSAL (ID_SUCURSAL),
    CONSTRAINT CK_BITA_OPERACION CHECK (OPERACION_BITA IN ('INSERT','UPDATE','DELETE','LOGIN','LOGOUT','ANULAR','CONSULTA'))
) TABLESPACE TBS_AUDITORIA;

COMMENT ON TABLE  AUD_BITACORA                      IS 'Bitacora general de operaciones realizadas por los usuarios del sistema.';
COMMENT ON COLUMN AUD_BITACORA.ID_BITACORA          IS 'Identificador unico del registro de bitacora.';
COMMENT ON COLUMN AUD_BITACORA.ID_USUARIO           IS 'Usuario de la aplicacion que realizo la operacion. FK a SEG_USUARIO.';
COMMENT ON COLUMN AUD_BITACORA.ID_SUCURSAL          IS 'Sucursal desde la que se realizo. FK a SEG_SUCURSAL.';
COMMENT ON COLUMN AUD_BITACORA.TABLA_BITA           IS 'Nombre de la tabla afectada.';
COMMENT ON COLUMN AUD_BITACORA.LLAVE_REGISTRO_BITA  IS 'Valor de la llave primaria del registro afectado.';
COMMENT ON COLUMN AUD_BITACORA.OPERACION_BITA       IS 'Operacion: INSERT, UPDATE, DELETE, LOGIN, LOGOUT, ANULAR o CONSULTA.';
COMMENT ON COLUMN AUD_BITACORA.MODULO_BITA          IS 'Modulo funcional desde el que se hizo la operacion.';
COMMENT ON COLUMN AUD_BITACORA.DESCRIPCION_BITA     IS 'Descripcion de lo ocurrido.';
COMMENT ON COLUMN AUD_BITACORA.DIRECCION_IP_BITA    IS 'Direccion IP del equipo cliente.';
COMMENT ON COLUMN AUD_BITACORA.FECHA_BITA           IS 'Fecha y hora de la operacion.';
COMMENT ON COLUMN AUD_BITACORA.USUARIO_CREA_BITA    IS 'Usuario de base de datos que inserto el registro.';
COMMENT ON COLUMN AUD_BITACORA.FECHA_CREA_BITA      IS 'Fecha y hora de creacion del registro.';

PROMPT Modulo AUD_ creado: 1 tablas, 1 secuencias.


--------------------------------------------------------------------------------
-- SECCION 11 de 12: indices
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Indices secundarios: sobre llaves foraneas y sobre columnas de busqueda.
-- Los indices primarios (PK) y unicos (UK, UX) se crean junto con cada tabla.
-- No se indexa una FK cuando ya es prefijo de una PK o UK de la misma tabla.
--------------------------------------------------------------------------------
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- 1. INDICES SOBRE LLAVES FORANEAS

-- Modulo PER_
CREATE INDEX IX_PEFI_PERS ON PER_PERSONA_FISICA (ID_PERSONA_FISICA, TIPO_PERS) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PEFI_PAIS_NAC ON PER_PERSONA_FISICA (ID_PAIS_NACIONALIDAD) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PEFI_PAIS_RES ON PER_PERSONA_FISICA (ID_PAIS_RESIDENCIA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PEJU_PERS ON PER_PERSONA_JURIDICA (ID_PERSONA_JURIDICA, TIPO_PERS) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PEJU_PAIS_ORI ON PER_PERSONA_JURIDICA (ID_PAIS_ORIGEN) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DIRE_DIST ON PER_DIRECCION (ID_DISTRITO) TABLESPACE TBS_INDICES;

-- Modulo SEG_
CREATE INDEX IX_EMP_PEJU ON SEG_EMPRESA (ID_PERSONA_JURIDICA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_SUC_EMP ON SEG_SUCURSAL (ID_EMPRESA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_SUC_DIST ON SEG_SUCURSAL (ID_DISTRITO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_USSU_SUC ON SEG_USUARIO_SUCURSAL (ID_SUCURSAL) TABLESPACE TBS_INDICES;

-- Modulo PRO_
CREATE INDEX IX_FAMI_FAMI_PADRE ON PRO_FAMILIA_PRODUCTO (ID_FAMILIA_PRODUCTO_PADRE) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PROD_FAMI ON PRO_PRODUCTO (ID_FAMILIA_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PROD_PROVE ON PRO_PRODUCTO (ID_PROVEEDOR) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PROD_IMPU ON PRO_PRODUCTO (ID_IMPUESTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_COBA_PROD ON PRO_CODIGO_BARRA (ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PRSU_SUC ON PRO_PRODUCTO_SUCURSAL (ID_SUCURSAL) TABLESPACE TBS_INDICES;
CREATE INDEX IX_SERV_IMPU ON PRO_SERVICIO (ID_IMPUESTO) TABLESPACE TBS_INDICES;

-- Modulo INV_
CREATE INDEX IX_BODE_SUC ON INV_BODEGA (ID_SUCURSAL) TABLESPACE TBS_INDICES;
CREATE INDEX IX_EXIS_PROD ON INV_EXISTENCIA (ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_EXIS_LOTE ON INV_EXISTENCIA (ID_LOTE, ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_MOVI_USU ON INV_MOVIMIENTO (ID_USUARIO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_MODE_PROD ON INV_MOVIMIENTO_DET (ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_MODE_LOTE ON INV_MOVIMIENTO_DET (ID_LOTE, ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_TRAS_BODE_ORI ON INV_TRASLADO (ID_BODEGA_ORIGEN) TABLESPACE TBS_INDICES;
CREATE INDEX IX_TRAS_USU_ENV ON INV_TRASLADO (ID_USUARIO_ENVIA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_TRAS_USU_REC ON INV_TRASLADO (ID_USUARIO_RECIBE) TABLESPACE TBS_INDICES;
CREATE INDEX IX_TRDE_PROD ON INV_TRASLADO_DET (ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_TRDE_LOTE ON INV_TRASLADO_DET (ID_LOTE, ID_PRODUCTO) TABLESPACE TBS_INDICES;

-- Modulo COM_
CREATE INDEX IX_FACO_BODE ON COM_FACTURA_COMPRA (ID_BODEGA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_FACO_USU ON COM_FACTURA_COMPRA (ID_USUARIO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_FCDE_PROD ON COM_FACTURA_COMPRA_DET (ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_FCDE_LOTE ON COM_FACTURA_COMPRA_DET (ID_LOTE, ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_ABPA_FACO ON COM_ABONO_PAGAR (ID_FACTURA_COMPRA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_ABPA_USU ON COM_ABONO_PAGAR (ID_USUARIO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DEVC_FACO ON COM_DEVOLUCION (ID_FACTURA_COMPRA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DEVC_BODE ON COM_DEVOLUCION (ID_BODEGA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DEVC_USU ON COM_DEVOLUCION (ID_USUARIO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DVCD_FCDE ON COM_DEVOLUCION_DET (ID_FACTURA_COMPRA_DET) TABLESPACE TBS_INDICES;
CREATE INDEX IX_NCCO_USU ON COM_NOTA_CREDITO (ID_USUARIO) TABLESPACE TBS_INDICES;

-- Modulo VEN_
CREATE INDEX IX_FVDE_PROD ON VEN_FACTURA_DET (ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_FVDE_SERV ON VEN_FACTURA_DET (ID_SERVICIO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_FVDE_LOTE ON VEN_FACTURA_DET (ID_LOTE, ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_ABCO_FAVE ON VEN_ABONO_COBRAR (ID_FACTURA_VENTA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_ABCO_USU ON VEN_ABONO_COBRAR (ID_USUARIO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DEVV_FAVE ON VEN_DEVOLUCION (ID_FACTURA_VENTA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DEVV_BODE ON VEN_DEVOLUCION (ID_BODEGA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DEVV_USU ON VEN_DEVOLUCION (ID_USUARIO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DVVD_FVDE ON VEN_DEVOLUCION_DET (ID_FACTURA_VENTA_DET) TABLESPACE TBS_INDICES;
CREATE INDEX IX_NCVE_USU ON VEN_NOTA_CREDITO (ID_USUARIO) TABLESPACE TBS_INDICES;

-- Modulo PRM_
CREATE INDEX IX_PROM_SUC ON PRM_PROMOCION (ID_SUCURSAL) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PATR_PROD ON PRM_PATROCINADOR (ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PREM_PROD ON PRM_PREMIO (ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_ACLI_FAVE ON PRM_ACCION_CLIENTE (ID_FACTURA_VENTA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_ACLI_PREM ON PRM_ACCION_CLIENTE (ID_PREMIO, ID_PROMOCION) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DSCT_SUC ON PRM_DESCUENTO (ID_SUCURSAL) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DSRE_DSCT ON PRM_DESCUENTO_REGLA (ID_DESCUENTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DSRE_FAMI ON PRM_DESCUENTO_REGLA (ID_FAMILIA_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DSRE_PROVE ON PRM_DESCUENTO_REGLA (ID_PROVEEDOR) TABLESPACE TBS_INDICES;

-- Modulo AUD_
CREATE INDEX IX_BITA_USU ON AUD_BITACORA (ID_USUARIO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_BITA_SUC ON AUD_BITACORA (ID_SUCURSAL) TABLESPACE TBS_INDICES;

-- 2. INDICES DE BUSQUEDA

CREATE INDEX IX_PERS_NUM_IDENT ON PER_PERSONA (NUM_IDENTIFICACION_PERS) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PEFI_APELLIDOS ON PER_PERSONA_FISICA (APELLIDO1_PEFI, APELLIDO2_PEFI, NOMBRE_PEFI) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PEJU_RAZON ON PER_PERSONA_JURIDICA (RAZON_SOCIAL_PEJU) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PROD_NOMBRE ON PRO_PRODUCTO (NOMBRE_PROD) TABLESPACE TBS_INDICES;
CREATE INDEX IX_LOTE_VENCIMIENTO ON PRO_LOTE (FECHA_VENCIM_LOTE, ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_LOTE_INGRESO ON PRO_LOTE (FECHA_INGRESO_LOTE, ID_PRODUCTO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_MOVI_BODE_FECHA ON INV_MOVIMIENTO (ID_BODEGA, FECHA_MOVI) TABLESPACE TBS_INDICES;
CREATE INDEX IX_TRAS_DEST_ESTADO ON INV_TRASLADO (ID_BODEGA_DESTINO, ESTADO_TRAS) TABLESPACE TBS_INDICES;
CREATE INDEX IX_FACO_FECHA ON COM_FACTURA_COMPRA (FECHA_FACO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_FACO_CRED_VENCIM ON COM_FACTURA_COMPRA (ES_CREDITO_FACO, FECHA_VENCIM_FACO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_NCCO_NUM ON COM_NOTA_CREDITO (NUM_NOTA_NCCO) TABLESPACE TBS_INDICES;
CREATE INDEX IX_FAVE_SUC_FECHA ON VEN_FACTURA (ID_SUCURSAL, FECHA_FAVE) TABLESPACE TBS_INDICES;
CREATE INDEX IX_FAVE_CLI_FECHA ON VEN_FACTURA (ID_CLIENTE, FECHA_FAVE) TABLESPACE TBS_INDICES;
CREATE INDEX IX_FAVE_USU_FECHA ON VEN_FACTURA (ID_USUARIO, FECHA_FAVE) TABLESPACE TBS_INDICES;
CREATE INDEX IX_FAVE_CRED_VENCIM ON VEN_FACTURA (ES_CREDITO_FAVE, FECHA_VENCIM_FAVE) TABLESPACE TBS_INDICES;
CREATE INDEX IX_PROM_VIGENCIA ON PRM_PROMOCION (FECHA_INICIO_PROM, FECHA_FIN_PROM) TABLESPACE TBS_INDICES;
CREATE INDEX IX_DSCT_VIGENCIA ON PRM_DESCUENTO (FECHA_INICIO_DSCT, FECHA_FIN_DSCT, PRIORIDAD_DSCT) TABLESPACE TBS_INDICES;
CREATE INDEX IX_BITA_FECHA ON AUD_BITACORA (FECHA_BITA) TABLESPACE TBS_INDICES;
CREATE INDEX IX_BITA_TABLA_FECHA ON AUD_BITACORA (TABLA_BITA, FECHA_BITA) TABLESPACE TBS_INDICES;

PROMPT Indices secundarios creados: 60 sobre llaves foraneas, 19 de busqueda.


--------------------------------------------------------------------------------
-- SECCION 12 de 12: datos de prueba
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Datos de prueba: minimo 5 registros por tabla
--------------------------------------------------------------------------------
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- MODULO CAT_ : Jerarquia geografica

-- CAT_PAIS (5 registros)
INSERT INTO CAT_PAIS (ID_PAIS, CODIGO_ISO_PAIS, NOMBRE_PAIS, COD_TELEFONICO_PAIS)
VALUES (1, 'CRI', 'Costa Rica', '506');
INSERT INTO CAT_PAIS (ID_PAIS, CODIGO_ISO_PAIS, NOMBRE_PAIS, COD_TELEFONICO_PAIS)
VALUES (2, 'PAN', 'Panama', '507');
INSERT INTO CAT_PAIS (ID_PAIS, CODIGO_ISO_PAIS, NOMBRE_PAIS, COD_TELEFONICO_PAIS)
VALUES (3, 'NIC', 'Nicaragua', '505');
INSERT INTO CAT_PAIS (ID_PAIS, CODIGO_ISO_PAIS, NOMBRE_PAIS, COD_TELEFONICO_PAIS)
VALUES (4, 'USA', 'Estados Unidos', '1');
INSERT INTO CAT_PAIS (ID_PAIS, CODIGO_ISO_PAIS, NOMBRE_PAIS, COD_TELEFONICO_PAIS)
VALUES (5, 'COL', 'Colombia', '57');

-- CAT_PROVINCIA (5 registros)
INSERT INTO CAT_PROVINCIA (ID_PROVINCIA, ID_PAIS, CODIGO_PROVI, NOMBRE_PROVI)
VALUES (1, 1, '1', 'San Jose');
INSERT INTO CAT_PROVINCIA (ID_PROVINCIA, ID_PAIS, CODIGO_PROVI, NOMBRE_PROVI)
VALUES (2, 1, '2', 'Alajuela');
INSERT INTO CAT_PROVINCIA (ID_PROVINCIA, ID_PAIS, CODIGO_PROVI, NOMBRE_PROVI)
VALUES (3, 1, '3', 'Cartago');
INSERT INTO CAT_PROVINCIA (ID_PROVINCIA, ID_PAIS, CODIGO_PROVI, NOMBRE_PROVI)
VALUES (4, 1, '6', 'Puntarenas');
INSERT INTO CAT_PROVINCIA (ID_PROVINCIA, ID_PAIS, CODIGO_PROVI, NOMBRE_PROVI)
VALUES (5, 1, '7', 'Limon');

-- CAT_CANTON (5 registros)
INSERT INTO CAT_CANTON (ID_CANTON, ID_PROVINCIA, CODIGO_CANT, NOMBRE_CANT)
VALUES (1, 1, '19', 'Perez Zeledon');
INSERT INTO CAT_CANTON (ID_CANTON, ID_PROVINCIA, CODIGO_CANT, NOMBRE_CANT)
VALUES (2, 4, '10', 'Corredores');
INSERT INTO CAT_CANTON (ID_CANTON, ID_PROVINCIA, CODIGO_CANT, NOMBRE_CANT)
VALUES (3, 4, '07', 'Golfito');
INSERT INTO CAT_CANTON (ID_CANTON, ID_PROVINCIA, CODIGO_CANT, NOMBRE_CANT)
VALUES (4, 4, '03', 'Buenos Aires');
INSERT INTO CAT_CANTON (ID_CANTON, ID_PROVINCIA, CODIGO_CANT, NOMBRE_CANT)
VALUES (5, 1, '01', 'San Jose');

-- CAT_DISTRITO (5 registros)
INSERT INTO CAT_DISTRITO (ID_DISTRITO, ID_CANTON, CODIGO_DIST, NOMBRE_DIST, CODIGO_POSTAL_DIST)
VALUES (1, 1, '01', 'San Isidro de El General', '11901');
INSERT INTO CAT_DISTRITO (ID_DISTRITO, ID_CANTON, CODIGO_DIST, NOMBRE_DIST, CODIGO_POSTAL_DIST)
VALUES (2, 2, '01', 'Corredor', '61003');
INSERT INTO CAT_DISTRITO (ID_DISTRITO, ID_CANTON, CODIGO_DIST, NOMBRE_DIST, CODIGO_POSTAL_DIST)
VALUES (3, 3, '01', 'Golfito', '60701');
INSERT INTO CAT_DISTRITO (ID_DISTRITO, ID_CANTON, CODIGO_DIST, NOMBRE_DIST, CODIGO_POSTAL_DIST)
VALUES (4, 4, '01', 'Buenos Aires', '60301');
INSERT INTO CAT_DISTRITO (ID_DISTRITO, ID_CANTON, CODIGO_DIST, NOMBRE_DIST, CODIGO_POSTAL_DIST)
VALUES (5, 5, '01', 'Carmen', '10101');

-- MODULO PER_ : Personas, clientes y proveedores

-- PER_PERSONA (16 registros)
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (1, 'N', '118540236', TO_DATE('2024-02-10','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (2, 'N', '603780145', TO_DATE('2024-02-10','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (3, 'E', '155812340077', TO_DATE('2024-02-10','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (4, 'N', '110230458', TO_DATE('2024-02-10','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (5, 'J', '3101245789', TO_DATE('2024-01-15','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (6, 'J', '3101008652', TO_DATE('2024-01-15','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (7, 'J', '3101112233', TO_DATE('2024-01-15','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (8, 'J', '3101445566', TO_DATE('2024-01-15','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (9, 'J', '3101778899', TO_DATE('2024-01-15','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (10, 'J', '3101334455', TO_DATE('2024-01-15','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (11, 'N', '604120389', TO_DATE('2024-02-10','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (12, 'N', '113450672', TO_DATE('2024-02-10','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (13, 'N', '602890134', TO_DATE('2024-02-10','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (14, 'N', '117760245', TO_DATE('2024-02-10','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (15, 'N', '605230917', TO_DATE('2024-02-10','YYYY-MM-DD'));
INSERT INTO PER_PERSONA (ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS)
VALUES (16, 'J', '3101900001', TO_DATE('2024-01-15','YYYY-MM-DD'));

-- PER_PERSONA_FISICA (9 registros)
INSERT INTO PER_PERSONA_FISICA (ID_PERSONA_FISICA, TIPO_PERS, NOMBRE_PEFI, APELLIDO1_PEFI, APELLIDO2_PEFI, SEXO_PEFI, FECHA_NACIMIENTO_PEFI, ESTADO_CIVIL_PEFI, ESCOLARIDAD_PEFI, ID_PAIS_NACIONALIDAD, ID_PAIS_RESIDENCIA, PUESTO_PEFI, EMPRESA_LABORA_PEFI, ES_ASEGURADO_PEFI)
VALUES (1, 'N', 'Cliente', 'Contado', NULL, 'O', TO_DATE('1990-01-01','YYYY-MM-DD'), NULL, NULL, 1, 1, NULL, NULL, 'N');
INSERT INTO PER_PERSONA_FISICA (ID_PERSONA_FISICA, TIPO_PERS, NOMBRE_PEFI, APELLIDO1_PEFI, APELLIDO2_PEFI, SEXO_PEFI, FECHA_NACIMIENTO_PEFI, ESTADO_CIVIL_PEFI, ESCOLARIDAD_PEFI, ID_PAIS_NACIONALIDAD, ID_PAIS_RESIDENCIA, PUESTO_PEFI, EMPRESA_LABORA_PEFI, ES_ASEGURADO_PEFI)
VALUES (2, 'N', 'Marisol', 'Vargas', 'Chinchilla', 'F', TO_DATE('1988-06-14','YYYY-MM-DD'), 'C', 'U', 1, 1, 'Contadora', 'Cooperativa Agricola del General', 'S');
INSERT INTO PER_PERSONA_FISICA (ID_PERSONA_FISICA, TIPO_PERS, NOMBRE_PEFI, APELLIDO1_PEFI, APELLIDO2_PEFI, SEXO_PEFI, FECHA_NACIMIENTO_PEFI, ESTADO_CIVIL_PEFI, ESCOLARIDAD_PEFI, ID_PAIS_NACIONALIDAD, ID_PAIS_RESIDENCIA, PUESTO_PEFI, EMPRESA_LABORA_PEFI, ES_ASEGURADO_PEFI)
VALUES (3, 'E', 'Andres', 'Molina', NULL, 'M', TO_DATE('1979-11-23','YYYY-MM-DD'), 'C', 'T', 3, 1, 'Operario de produccion', 'Agroindustrias del Sur', 'N');
INSERT INTO PER_PERSONA_FISICA (ID_PERSONA_FISICA, TIPO_PERS, NOMBRE_PEFI, APELLIDO1_PEFI, APELLIDO2_PEFI, SEXO_PEFI, FECHA_NACIMIENTO_PEFI, ESTADO_CIVIL_PEFI, ESCOLARIDAD_PEFI, ID_PAIS_NACIONALIDAD, ID_PAIS_RESIDENCIA, PUESTO_PEFI, EMPRESA_LABORA_PEFI, ES_ASEGURADO_PEFI)
VALUES (4, 'N', 'Keylor', 'Jimenez', 'Sanabria', 'M', TO_DATE('1995-03-08','YYYY-MM-DD'), 'S', 'U', 1, 1, 'Docente', 'Ministerio de Educacion Publica', 'S');
INSERT INTO PER_PERSONA_FISICA (ID_PERSONA_FISICA, TIPO_PERS, NOMBRE_PEFI, APELLIDO1_PEFI, APELLIDO2_PEFI, SEXO_PEFI, FECHA_NACIMIENTO_PEFI, ESTADO_CIVIL_PEFI, ESCOLARIDAD_PEFI, ID_PAIS_NACIONALIDAD, ID_PAIS_RESIDENCIA, PUESTO_PEFI, EMPRESA_LABORA_PEFI, ES_ASEGURADO_PEFI)
VALUES (11, 'N', 'Hairol', 'Romero', 'Segura', 'M', TO_DATE('1985-09-17','YYYY-MM-DD'), 'C', 'G', 1, 1, 'Gerente general', 'Supermercados Brunca', 'S');
INSERT INTO PER_PERSONA_FISICA (ID_PERSONA_FISICA, TIPO_PERS, NOMBRE_PEFI, APELLIDO1_PEFI, APELLIDO2_PEFI, SEXO_PEFI, FECHA_NACIMIENTO_PEFI, ESTADO_CIVIL_PEFI, ESCOLARIDAD_PEFI, ID_PAIS_NACIONALIDAD, ID_PAIS_RESIDENCIA, PUESTO_PEFI, EMPRESA_LABORA_PEFI, ES_ASEGURADO_PEFI)
VALUES (12, 'N', 'Jeremy', 'Elizondo', 'Mora', 'M', TO_DATE('1992-12-02','YYYY-MM-DD'), 'S', 'G', 1, 1, 'Jefe de bodega', 'Supermercados Brunca', 'S');
INSERT INTO PER_PERSONA_FISICA (ID_PERSONA_FISICA, TIPO_PERS, NOMBRE_PEFI, APELLIDO1_PEFI, APELLIDO2_PEFI, SEXO_PEFI, FECHA_NACIMIENTO_PEFI, ESTADO_CIVIL_PEFI, ESCOLARIDAD_PEFI, ID_PAIS_NACIONALIDAD, ID_PAIS_RESIDENCIA, PUESTO_PEFI, EMPRESA_LABORA_PEFI, ES_ASEGURADO_PEFI)
VALUES (13, 'N', 'Gabriela', 'Urena', 'Solis', 'F', TO_DATE('1993-07-21','YYYY-MM-DD'), 'S', 'U', 1, 1, 'Cajera', 'Supermercados Brunca', 'S');
INSERT INTO PER_PERSONA_FISICA (ID_PERSONA_FISICA, TIPO_PERS, NOMBRE_PEFI, APELLIDO1_PEFI, APELLIDO2_PEFI, SEXO_PEFI, FECHA_NACIMIENTO_PEFI, ESTADO_CIVIL_PEFI, ESCOLARIDAD_PEFI, ID_PAIS_NACIONALIDAD, ID_PAIS_RESIDENCIA, PUESTO_PEFI, EMPRESA_LABORA_PEFI, ES_ASEGURADO_PEFI)
VALUES (14, 'N', 'Luis', 'Castro', 'Fallas', 'M', TO_DATE('1980-04-05','YYYY-MM-DD'), 'C', 'T', 1, 1, 'Encargado de bodega', 'Supermercados Brunca', 'S');
INSERT INTO PER_PERSONA_FISICA (ID_PERSONA_FISICA, TIPO_PERS, NOMBRE_PEFI, APELLIDO1_PEFI, APELLIDO2_PEFI, SEXO_PEFI, FECHA_NACIMIENTO_PEFI, ESTADO_CIVIL_PEFI, ESCOLARIDAD_PEFI, ID_PAIS_NACIONALIDAD, ID_PAIS_RESIDENCIA, PUESTO_PEFI, EMPRESA_LABORA_PEFI, ES_ASEGURADO_PEFI)
VALUES (15, 'N', 'Daniela', 'Rojas', 'Ceciliano', 'F', TO_DATE('1997-10-30','YYYY-MM-DD'), 'S', 'U', 1, 1, 'Contadora', 'Supermercados Brunca', 'S');

-- PER_PERSONA_JURIDICA (7 registros)
INSERT INTO PER_PERSONA_JURIDICA (ID_PERSONA_JURIDICA, TIPO_PERS, RAZON_SOCIAL_PEJU, NOMBRE_COMERCIAL_PEJU, FECHA_CONSTITUCION_PEJU, ID_PAIS_ORIGEN, SITIO_WEB_PEJU)
VALUES (5, 'J', 'Constructora del Sur Sociedad Anonima', 'Constructora del Sur', TO_DATE('2010-05-12','YYYY-MM-DD'), 1, 'https://www.constructoradelsur.cr');
INSERT INTO PER_PERSONA_JURIDICA (ID_PERSONA_JURIDICA, TIPO_PERS, RAZON_SOCIAL_PEJU, NOMBRE_COMERCIAL_PEJU, FECHA_CONSTITUCION_PEJU, ID_PAIS_ORIGEN, SITIO_WEB_PEJU)
VALUES (6, 'J', 'Distribuidora Alimenticia Nacional S.A.', 'DINASA', TO_DATE('2001-03-20','YYYY-MM-DD'), 1, 'https://www.dinasa.cr');
INSERT INTO PER_PERSONA_JURIDICA (ID_PERSONA_JURIDICA, TIPO_PERS, RAZON_SOCIAL_PEJU, NOMBRE_COMERCIAL_PEJU, FECHA_CONSTITUCION_PEJU, ID_PAIS_ORIGEN, SITIO_WEB_PEJU)
VALUES (7, 'J', 'Lacteos del Valle Sociedad Anonima', 'Lacteos del Valle', TO_DATE('2005-08-11','YYYY-MM-DD'), 1, 'https://www.lacteosdelvalle.cr');
INSERT INTO PER_PERSONA_JURIDICA (ID_PERSONA_JURIDICA, TIPO_PERS, RAZON_SOCIAL_PEJU, NOMBRE_COMERCIAL_PEJU, FECHA_CONSTITUCION_PEJU, ID_PAIS_ORIGEN, SITIO_WEB_PEJU)
VALUES (8, 'J', 'Importadora Brunca Limitada', 'Importadora Brunca', TO_DATE('2012-01-30','YYYY-MM-DD'), 1, 'https://www.importadorabrunca.cr');
INSERT INTO PER_PERSONA_JURIDICA (ID_PERSONA_JURIDICA, TIPO_PERS, RAZON_SOCIAL_PEJU, NOMBRE_COMERCIAL_PEJU, FECHA_CONSTITUCION_PEJU, ID_PAIS_ORIGEN, SITIO_WEB_PEJU)
VALUES (9, 'J', 'Productos de Limpieza Zeta S.A.', 'Limpieza Zeta', TO_DATE('2015-06-18','YYYY-MM-DD'), 1, 'https://www.limpiezazeta.cr');
INSERT INTO PER_PERSONA_JURIDICA (ID_PERSONA_JURIDICA, TIPO_PERS, RAZON_SOCIAL_PEJU, NOMBRE_COMERCIAL_PEJU, FECHA_CONSTITUCION_PEJU, ID_PAIS_ORIGEN, SITIO_WEB_PEJU)
VALUES (10, 'J', 'Carnes y Embutidos del Pacifico S.A.', 'Carnes del Pacifico', TO_DATE('2008-09-25','YYYY-MM-DD'), 1, 'https://www.carnesdelpacifico.cr');
INSERT INTO PER_PERSONA_JURIDICA (ID_PERSONA_JURIDICA, TIPO_PERS, RAZON_SOCIAL_PEJU, NOMBRE_COMERCIAL_PEJU, FECHA_CONSTITUCION_PEJU, ID_PAIS_ORIGEN, SITIO_WEB_PEJU)
VALUES (16, 'J', 'Supermercados Brunca Sociedad Anonima', 'Super Brunca', TO_DATE('2018-02-01','YYYY-MM-DD'), 1, 'https://www.superbrunca.cr');

-- PER_DIRECCION (5 registros)
INSERT INTO PER_DIRECCION (ID_DIRECCION, ID_PERSONA, TIPO_DIRE, ID_DISTRITO, SENNAS_EXACTAS_DIRE, ES_PRINCIPAL_DIRE)
VALUES (1, 2, 'C', 1, 'Barrio Lourdes, 200 metros sur de la escuela, casa color verde.', 'S');
INSERT INTO PER_DIRECCION (ID_DIRECCION, ID_PERSONA, TIPO_DIRE, ID_DISTRITO, SENNAS_EXACTAS_DIRE, ES_PRINCIPAL_DIRE)
VALUES (2, 2, 'T', 1, 'Centro comercial Plaza del General, local 14.', 'N');
INSERT INTO PER_DIRECCION (ID_DIRECCION, ID_PERSONA, TIPO_DIRE, ID_DISTRITO, SENNAS_EXACTAS_DIRE, ES_PRINCIPAL_DIRE)
VALUES (3, 3, 'C', 2, 'Urbanizacion La Colina, casa 27.', 'S');
INSERT INTO PER_DIRECCION (ID_DIRECCION, ID_PERSONA, TIPO_DIRE, ID_DISTRITO, SENNAS_EXACTAS_DIRE, ES_PRINCIPAL_DIRE)
VALUES (4, 6, 'T', 5, 'Avenida 10, calle 24, edificio corporativo DINASA.', 'S');
INSERT INTO PER_DIRECCION (ID_DIRECCION, ID_PERSONA, TIPO_DIRE, ID_DISTRITO, SENNAS_EXACTAS_DIRE, ES_PRINCIPAL_DIRE)
VALUES (5, 16, 'T', 1, 'Frente al parque central de San Isidro, edificio Super Brunca.', 'S');

-- PER_CONTACTO (6 registros)
INSERT INTO PER_CONTACTO (ID_CONTACTO, ID_PERSONA, TIPO_CONT, VALOR_CONT, ES_PRINCIPAL_CONT)
VALUES (1, 2, 'C', '87451236', 'S');
INSERT INTO PER_CONTACTO (ID_CONTACTO, ID_PERSONA, TIPO_CONT, VALOR_CONT, ES_PRINCIPAL_CONT)
VALUES (2, 2, 'E', 'marisol.vargas@correo.cr', 'S');
INSERT INTO PER_CONTACTO (ID_CONTACTO, ID_PERSONA, TIPO_CONT, VALOR_CONT, ES_PRINCIPAL_CONT)
VALUES (3, 3, 'C', '83120945', 'S');
INSERT INTO PER_CONTACTO (ID_CONTACTO, ID_PERSONA, TIPO_CONT, VALOR_CONT, ES_PRINCIPAL_CONT)
VALUES (4, 6, 'T', '22581400', 'S');
INSERT INTO PER_CONTACTO (ID_CONTACTO, ID_PERSONA, TIPO_CONT, VALOR_CONT, ES_PRINCIPAL_CONT)
VALUES (5, 6, 'F', '22581401', 'N');
INSERT INTO PER_CONTACTO (ID_CONTACTO, ID_PERSONA, TIPO_CONT, VALOR_CONT, ES_PRINCIPAL_CONT)
VALUES (6, 16, 'E', 'info@superbrunca.cr', 'S');

-- PER_CLIENTE (5 registros)
INSERT INTO PER_CLIENTE (ID_CLIENTE, ID_PERSONA, CODIGO_CLI, FECHA_INGRESO_CLI, ES_PREFERENCIAL_CLI, MONTO_MAX_CREDITO_CLI, DIAS_CREDITO_CLI, ES_DEFECTO_CLI)
VALUES (1, 1, 'CLI-000000', TO_DATE('2024-02-10','YYYY-MM-DD'), 'N', 0, 0, 'S');
INSERT INTO PER_CLIENTE (ID_CLIENTE, ID_PERSONA, CODIGO_CLI, FECHA_INGRESO_CLI, ES_PREFERENCIAL_CLI, MONTO_MAX_CREDITO_CLI, DIAS_CREDITO_CLI, ES_DEFECTO_CLI)
VALUES (2, 2, 'CLI-000001', TO_DATE('2024-03-05','YYYY-MM-DD'), 'N', 0, 0, 'N');
INSERT INTO PER_CLIENTE (ID_CLIENTE, ID_PERSONA, CODIGO_CLI, FECHA_INGRESO_CLI, ES_PREFERENCIAL_CLI, MONTO_MAX_CREDITO_CLI, DIAS_CREDITO_CLI, ES_DEFECTO_CLI)
VALUES (3, 3, 'CLI-000002', TO_DATE('2024-04-18','YYYY-MM-DD'), 'S', 250000, 30, 'N');
INSERT INTO PER_CLIENTE (ID_CLIENTE, ID_PERSONA, CODIGO_CLI, FECHA_INGRESO_CLI, ES_PREFERENCIAL_CLI, MONTO_MAX_CREDITO_CLI, DIAS_CREDITO_CLI, ES_DEFECTO_CLI)
VALUES (4, 4, 'CLI-000003', TO_DATE('2025-01-22','YYYY-MM-DD'), 'N', 0, 0, 'N');
INSERT INTO PER_CLIENTE (ID_CLIENTE, ID_PERSONA, CODIGO_CLI, FECHA_INGRESO_CLI, ES_PREFERENCIAL_CLI, MONTO_MAX_CREDITO_CLI, DIAS_CREDITO_CLI, ES_DEFECTO_CLI)
VALUES (5, 5, 'CLI-000004', TO_DATE('2025-06-30','YYYY-MM-DD'), 'S', 1500000, 45, 'N');

-- PER_PROVEEDOR (5 registros)
INSERT INTO PER_PROVEEDOR (ID_PROVEEDOR, ID_PERSONA_JURIDICA, CODIGO_PROVE, FECHA_INGRESO_PROVE, LIMITE_CREDITO_PROVE, DIAS_CREDITO_PROVE, NOMBRE_CONTACTO_PROVE)
VALUES (1, 6, 'PRV-0001', TO_DATE('2024-01-20','YYYY-MM-DD'), 8000000, 30, 'Randall Mora Quesada');
INSERT INTO PER_PROVEEDOR (ID_PROVEEDOR, ID_PERSONA_JURIDICA, CODIGO_PROVE, FECHA_INGRESO_PROVE, LIMITE_CREDITO_PROVE, DIAS_CREDITO_PROVE, NOMBRE_CONTACTO_PROVE)
VALUES (2, 7, 'PRV-0002', TO_DATE('2024-02-14','YYYY-MM-DD'), 4500000, 15, 'Silvia Barrantes Leon');
INSERT INTO PER_PROVEEDOR (ID_PROVEEDOR, ID_PERSONA_JURIDICA, CODIGO_PROVE, FECHA_INGRESO_PROVE, LIMITE_CREDITO_PROVE, DIAS_CREDITO_PROVE, NOMBRE_CONTACTO_PROVE)
VALUES (3, 8, 'PRV-0003', TO_DATE('2024-05-03','YYYY-MM-DD'), 2000000, 30, 'Oscar Delgado Pineda');
INSERT INTO PER_PROVEEDOR (ID_PROVEEDOR, ID_PERSONA_JURIDICA, CODIGO_PROVE, FECHA_INGRESO_PROVE, LIMITE_CREDITO_PROVE, DIAS_CREDITO_PROVE, NOMBRE_CONTACTO_PROVE)
VALUES (4, 9, 'PRV-0004', TO_DATE('2025-02-11','YYYY-MM-DD'), 1200000, 8, 'Melissa Aguilar Ruiz');
INSERT INTO PER_PROVEEDOR (ID_PROVEEDOR, ID_PERSONA_JURIDICA, CODIGO_PROVE, FECHA_INGRESO_PROVE, LIMITE_CREDITO_PROVE, DIAS_CREDITO_PROVE, NOMBRE_CONTACTO_PROVE)
VALUES (5, 10, 'PRV-0005', TO_DATE('2025-04-09','YYYY-MM-DD'), 6000000, 21, 'Jose Pablo Herrera Gomez');

-- MODULO SEG_ : Configuracion del negocio, sucursales y usuarios

-- SEG_EMPRESA (5 registros)
INSERT INTO SEG_EMPRESA (ID_EMPRESA, ID_PERSONA_JURIDICA, TIPO_NEGOCIO_EMP, NOMBRE_SISTEMA_EMP, MONEDA_BASE_EMP, FECHA_INICIO_OP_EMP, ESTADO_EMP)
VALUES (1, 16, 'SUPERMERCADO', 'Super Brunca - Punto de Venta', 'CRC', TO_DATE('2026-01-01','YYYY-MM-DD'), 'A');
INSERT INTO SEG_EMPRESA (ID_EMPRESA, ID_PERSONA_JURIDICA, TIPO_NEGOCIO_EMP, NOMBRE_SISTEMA_EMP, MONEDA_BASE_EMP, FECHA_INICIO_OP_EMP, ESTADO_EMP)
VALUES (2, 16, 'SUPERMERCADO', 'Super Brunca - Configuracion 2025', 'CRC', TO_DATE('2025-01-01','YYYY-MM-DD'), 'I');
INSERT INTO SEG_EMPRESA (ID_EMPRESA, ID_PERSONA_JURIDICA, TIPO_NEGOCIO_EMP, NOMBRE_SISTEMA_EMP, MONEDA_BASE_EMP, FECHA_INICIO_OP_EMP, ESTADO_EMP)
VALUES (3, 16, 'SUPERMERCADO', 'Super Brunca - Configuracion 2024', 'CRC', TO_DATE('2024-01-01','YYYY-MM-DD'), 'I');
INSERT INTO SEG_EMPRESA (ID_EMPRESA, ID_PERSONA_JURIDICA, TIPO_NEGOCIO_EMP, NOMBRE_SISTEMA_EMP, MONEDA_BASE_EMP, FECHA_INICIO_OP_EMP, ESTADO_EMP)
VALUES (4, 16, 'SUMINISTROS', 'Suministros Brunca - Configuracion 2023', 'CRC', TO_DATE('2023-01-01','YYYY-MM-DD'), 'I');
INSERT INTO SEG_EMPRESA (ID_EMPRESA, ID_PERSONA_JURIDICA, TIPO_NEGOCIO_EMP, NOMBRE_SISTEMA_EMP, MONEDA_BASE_EMP, FECHA_INICIO_OP_EMP, ESTADO_EMP)
VALUES (5, 16, 'FERRETERIA', 'Ferreteria Brunca - Configuracion inicial', 'CRC', TO_DATE('2018-02-01','YYYY-MM-DD'), 'I');

-- SEG_SUCURSAL (5 registros)
INSERT INTO SEG_SUCURSAL (ID_SUCURSAL, ID_EMPRESA, ID_DISTRITO, CODIGO_SUC, NOMBRE_SUC, SENNAS_EXACTAS_SUC, TELEFONO_SUC, ES_CASA_MATRIZ_SUC, FECHA_APERTURA_SUC)
VALUES (1, 1, 1, 'SUC-PZ01', 'Super Brunca San Isidro Centro', 'Frente al parque central de San Isidro de El General.', '27710101', 'S', TO_DATE('2018-02-01','YYYY-MM-DD'));
INSERT INTO SEG_SUCURSAL (ID_SUCURSAL, ID_EMPRESA, ID_DISTRITO, CODIGO_SUC, NOMBRE_SUC, SENNAS_EXACTAS_SUC, TELEFONO_SUC, ES_CASA_MATRIZ_SUC, FECHA_APERTURA_SUC)
VALUES (2, 1, 2, 'SUC-CT01', 'Super Brunca Ciudad Neily', 'Costado oeste del mercado municipal de Ciudad Neily.', '27830202', 'N', TO_DATE('2020-06-15','YYYY-MM-DD'));
INSERT INTO SEG_SUCURSAL (ID_SUCURSAL, ID_EMPRESA, ID_DISTRITO, CODIGO_SUC, NOMBRE_SUC, SENNAS_EXACTAS_SUC, TELEFONO_SUC, ES_CASA_MATRIZ_SUC, FECHA_APERTURA_SUC)
VALUES (3, 1, 3, 'SUC-GF01', 'Super Brunca Golfito', '200 metros norte del muelle de Golfito.', '27750303', 'N', TO_DATE('2022-03-10','YYYY-MM-DD'));
INSERT INTO SEG_SUCURSAL (ID_SUCURSAL, ID_EMPRESA, ID_DISTRITO, CODIGO_SUC, NOMBRE_SUC, SENNAS_EXACTAS_SUC, TELEFONO_SUC, ES_CASA_MATRIZ_SUC, FECHA_APERTURA_SUC)
VALUES (4, 1, 4, 'SUC-BA01', 'Super Brunca Buenos Aires', 'Contiguo a la terminal de buses de Buenos Aires.', '27300404', 'N', TO_DATE('2024-09-01','YYYY-MM-DD'));
INSERT INTO SEG_SUCURSAL (ID_SUCURSAL, ID_EMPRESA, ID_DISTRITO, CODIGO_SUC, NOMBRE_SUC, SENNAS_EXACTAS_SUC, TELEFONO_SUC, ES_CASA_MATRIZ_SUC, FECHA_APERTURA_SUC)
VALUES (5, 1, 5, 'SUC-SJ01', 'Super Brunca San Jose Centro', 'Avenida central, 100 metros este del Banco Nacional.', '22220505', 'N', TO_DATE('2025-11-20','YYYY-MM-DD'));

-- SEG_USUARIO (5 registros)
INSERT INTO SEG_USUARIO (ID_USUARIO, ID_PERSONA_FISICA, NOMBRE_USUARIO_USU, CLAVE_HASH_USU, ROL_USU, FECHA_ALTA_USU, INTENTOS_FALLIDOS_USU, DEBE_CAMBIAR_CLAVE_USU, ESTADO_USU)
VALUES (1, 11, 'hromero', '$2b$12$hromeroxxxxxxxxxxxxxxxK7pQrS9tUvWxYz0123456789abcd', 'ADMIN', TO_DATE('2026-01-05','YYYY-MM-DD'), 0, 'N', 'A');
INSERT INTO SEG_USUARIO (ID_USUARIO, ID_PERSONA_FISICA, NOMBRE_USUARIO_USU, CLAVE_HASH_USU, ROL_USU, FECHA_ALTA_USU, INTENTOS_FALLIDOS_USU, DEBE_CAMBIAR_CLAVE_USU, ESTADO_USU)
VALUES (2, 12, 'jelizondo', '$2b$12$jelizondoxxxxxxxxxxxxxK7pQrS9tUvWxYz0123456789abcd', 'SUPERVISOR', TO_DATE('2026-01-05','YYYY-MM-DD'), 0, 'N', 'A');
INSERT INTO SEG_USUARIO (ID_USUARIO, ID_PERSONA_FISICA, NOMBRE_USUARIO_USU, CLAVE_HASH_USU, ROL_USU, FECHA_ALTA_USU, INTENTOS_FALLIDOS_USU, DEBE_CAMBIAR_CLAVE_USU, ESTADO_USU)
VALUES (3, 13, 'gurena', '$2b$12$gurenaxxxxxxxxxxxxxxxxK7pQrS9tUvWxYz0123456789abcd', 'CAJERO', TO_DATE('2026-01-05','YYYY-MM-DD'), 0, 'N', 'A');
INSERT INTO SEG_USUARIO (ID_USUARIO, ID_PERSONA_FISICA, NOMBRE_USUARIO_USU, CLAVE_HASH_USU, ROL_USU, FECHA_ALTA_USU, INTENTOS_FALLIDOS_USU, DEBE_CAMBIAR_CLAVE_USU, ESTADO_USU)
VALUES (4, 14, 'lcastro', '$2b$12$lcastroxxxxxxxxxxxxxxxK7pQrS9tUvWxYz0123456789abcd', 'BODEGUERO', TO_DATE('2026-01-05','YYYY-MM-DD'), 0, 'N', 'A');
INSERT INTO SEG_USUARIO (ID_USUARIO, ID_PERSONA_FISICA, NOMBRE_USUARIO_USU, CLAVE_HASH_USU, ROL_USU, FECHA_ALTA_USU, INTENTOS_FALLIDOS_USU, DEBE_CAMBIAR_CLAVE_USU, ESTADO_USU)
VALUES (5, 15, 'drojas', '$2b$12$drojasxxxxxxxxxxxxxxxxK7pQrS9tUvWxYz0123456789abcd', 'CONTADOR', TO_DATE('2026-01-05','YYYY-MM-DD'), 0, 'N', 'B');

-- SEG_USUARIO_SUCURSAL (6 registros)
INSERT INTO SEG_USUARIO_SUCURSAL (ID_USUARIO_SUCURSAL, ID_USUARIO, ID_SUCURSAL, ES_DEFECTO_USSU, FECHA_ASIGNA_USSU)
VALUES (1, 1, 1, 'S', TO_DATE('2026-01-05','YYYY-MM-DD'));
INSERT INTO SEG_USUARIO_SUCURSAL (ID_USUARIO_SUCURSAL, ID_USUARIO, ID_SUCURSAL, ES_DEFECTO_USSU, FECHA_ASIGNA_USSU)
VALUES (2, 1, 2, 'N', TO_DATE('2026-01-05','YYYY-MM-DD'));
INSERT INTO SEG_USUARIO_SUCURSAL (ID_USUARIO_SUCURSAL, ID_USUARIO, ID_SUCURSAL, ES_DEFECTO_USSU, FECHA_ASIGNA_USSU)
VALUES (3, 2, 1, 'S', TO_DATE('2026-01-05','YYYY-MM-DD'));
INSERT INTO SEG_USUARIO_SUCURSAL (ID_USUARIO_SUCURSAL, ID_USUARIO, ID_SUCURSAL, ES_DEFECTO_USSU, FECHA_ASIGNA_USSU)
VALUES (4, 3, 2, 'S', TO_DATE('2026-01-05','YYYY-MM-DD'));
INSERT INTO SEG_USUARIO_SUCURSAL (ID_USUARIO_SUCURSAL, ID_USUARIO, ID_SUCURSAL, ES_DEFECTO_USSU, FECHA_ASIGNA_USSU)
VALUES (5, 4, 3, 'S', TO_DATE('2026-01-05','YYYY-MM-DD'));
INSERT INTO SEG_USUARIO_SUCURSAL (ID_USUARIO_SUCURSAL, ID_USUARIO, ID_SUCURSAL, ES_DEFECTO_USSU, FECHA_ASIGNA_USSU)
VALUES (6, 5, 4, 'S', TO_DATE('2026-01-05','YYYY-MM-DD'));

-- MODULO PRO_ : Productos, servicios, precios y lotes

-- PRO_FAMILIA_PRODUCTO (7 registros)
INSERT INTO PRO_FAMILIA_PRODUCTO (ID_FAMILIA_PRODUCTO, ID_FAMILIA_PRODUCTO_PADRE, CODIGO_FAMI, NOMBRE_FAMI)
VALUES (1, NULL, 'BEBIDAS', 'Bebidas');
INSERT INTO PRO_FAMILIA_PRODUCTO (ID_FAMILIA_PRODUCTO, ID_FAMILIA_PRODUCTO_PADRE, CODIGO_FAMI, NOMBRE_FAMI)
VALUES (2, NULL, 'CARNES', 'Carnes y embutidos');
INSERT INTO PRO_FAMILIA_PRODUCTO (ID_FAMILIA_PRODUCTO, ID_FAMILIA_PRODUCTO_PADRE, CODIGO_FAMI, NOMBRE_FAMI)
VALUES (3, NULL, 'VERDURAS', 'Verduras y frutas');
INSERT INTO PRO_FAMILIA_PRODUCTO (ID_FAMILIA_PRODUCTO, ID_FAMILIA_PRODUCTO_PADRE, CODIGO_FAMI, NOMBRE_FAMI)
VALUES (4, NULL, 'LACTEOS', 'Lacteos');
INSERT INTO PRO_FAMILIA_PRODUCTO (ID_FAMILIA_PRODUCTO, ID_FAMILIA_PRODUCTO_PADRE, CODIGO_FAMI, NOMBRE_FAMI)
VALUES (5, NULL, 'LIMPIEZA', 'Productos de limpieza');
INSERT INTO PRO_FAMILIA_PRODUCTO (ID_FAMILIA_PRODUCTO, ID_FAMILIA_PRODUCTO_PADRE, CODIGO_FAMI, NOMBRE_FAMI)
VALUES (6, NULL, 'ABARROTES', 'Abarrotes y granos');
INSERT INTO PRO_FAMILIA_PRODUCTO (ID_FAMILIA_PRODUCTO, ID_FAMILIA_PRODUCTO_PADRE, CODIGO_FAMI, NOMBRE_FAMI)
VALUES (7, 1, 'GASEOSAS', 'Bebidas gaseosas');

-- PRO_IMPUESTO (5 registros)
INSERT INTO PRO_IMPUESTO (ID_IMPUESTO, CODIGO_IMPU, NOMBRE_IMPU, PORCENTAJE_IMPU)
VALUES (1, 'IVA13', 'IVA tarifa general', 13);
INSERT INTO PRO_IMPUESTO (ID_IMPUESTO, CODIGO_IMPU, NOMBRE_IMPU, PORCENTAJE_IMPU)
VALUES (2, 'IVA4', 'IVA tarifa reducida 4%', 4);
INSERT INTO PRO_IMPUESTO (ID_IMPUESTO, CODIGO_IMPU, NOMBRE_IMPU, PORCENTAJE_IMPU)
VALUES (3, 'IVA2', 'IVA tarifa reducida 2%', 2);
INSERT INTO PRO_IMPUESTO (ID_IMPUESTO, CODIGO_IMPU, NOMBRE_IMPU, PORCENTAJE_IMPU)
VALUES (4, 'IVA1', 'IVA tarifa reducida canasta basica', 1);
INSERT INTO PRO_IMPUESTO (ID_IMPUESTO, CODIGO_IMPU, NOMBRE_IMPU, PORCENTAJE_IMPU)
VALUES (5, 'ISC10', 'Impuesto selectivo de consumo', 10);

-- PRO_PRODUCTO (8 registros)
INSERT INTO PRO_PRODUCTO (ID_PRODUCTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, ID_IMPUESTO, CODIGO_PROD, NOMBRE_PROD, UNIDAD_MEDIDA_PROD, PRECIO_COSTO_PROD, MANEJA_LOTE_PROD, STOCK_MINIMO_PROD)
VALUES (1, 7, 1, 1, 'PROD-0001', 'Coca Cola 2 litros', 'UND', 450, 'S', 50);
INSERT INTO PRO_PRODUCTO (ID_PRODUCTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, ID_IMPUESTO, CODIGO_PROD, NOMBRE_PROD, UNIDAD_MEDIDA_PROD, PRECIO_COSTO_PROD, MANEJA_LOTE_PROD, STOCK_MINIMO_PROD)
VALUES (2, 4, 2, 1, 'PROD-0002', 'Leche entera 1 litro', 'LT', 520, 'S', 30);
INSERT INTO PRO_PRODUCTO (ID_PRODUCTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, ID_IMPUESTO, CODIGO_PROD, NOMBRE_PROD, UNIDAD_MEDIDA_PROD, PRECIO_COSTO_PROD, MANEJA_LOTE_PROD, STOCK_MINIMO_PROD)
VALUES (3, 6, 3, 4, 'PROD-0003', 'Arroz blanco 1kg', 'KG', 675, 'N', 100);
INSERT INTO PRO_PRODUCTO (ID_PRODUCTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, ID_IMPUESTO, CODIGO_PROD, NOMBRE_PROD, UNIDAD_MEDIDA_PROD, PRECIO_COSTO_PROD, MANEJA_LOTE_PROD, STOCK_MINIMO_PROD)
VALUES (4, 6, 3, 4, 'PROD-0004', 'Frijol rojo 1kg', 'KG', 700, 'N', 80);
INSERT INTO PRO_PRODUCTO (ID_PRODUCTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, ID_IMPUESTO, CODIGO_PROD, NOMBRE_PROD, UNIDAD_MEDIDA_PROD, PRECIO_COSTO_PROD, MANEJA_LOTE_PROD, STOCK_MINIMO_PROD)
VALUES (5, 3, 3, NULL, 'PROD-0005', 'Tomate fresco 1kg', 'KG', 380, 'S', 40);
INSERT INTO PRO_PRODUCTO (ID_PRODUCTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, ID_IMPUESTO, CODIGO_PROD, NOMBRE_PROD, UNIDAD_MEDIDA_PROD, PRECIO_COSTO_PROD, MANEJA_LOTE_PROD, STOCK_MINIMO_PROD)
VALUES (6, 2, 5, 1, 'PROD-0006', 'Carne molida de res 1kg', 'KG', 2800, 'S', 25);
INSERT INTO PRO_PRODUCTO (ID_PRODUCTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, ID_IMPUESTO, CODIGO_PROD, NOMBRE_PROD, UNIDAD_MEDIDA_PROD, PRECIO_COSTO_PROD, MANEJA_LOTE_PROD, STOCK_MINIMO_PROD)
VALUES (7, 5, 4, 1, 'PROD-0007', 'Detergente en polvo 1kg', 'UND', 590, 'N', 40);
INSERT INTO PRO_PRODUCTO (ID_PRODUCTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, ID_IMPUESTO, CODIGO_PROD, NOMBRE_PROD, UNIDAD_MEDIDA_PROD, PRECIO_COSTO_PROD, MANEJA_LOTE_PROD, STOCK_MINIMO_PROD)
VALUES (8, 5, 4, 1, 'PROD-0008', 'Jabon de bano', 'UND', 320, 'N', 60);

-- PRO_CODIGO_BARRA (8 registros)
INSERT INTO PRO_CODIGO_BARRA (ID_CODIGO_BARRA, ID_PRODUCTO, CODIGO_COBA, ES_PRINCIPAL_COBA)
VALUES (1, 1, '7441234567890', 'S');
INSERT INTO PRO_CODIGO_BARRA (ID_CODIGO_BARRA, ID_PRODUCTO, CODIGO_COBA, ES_PRINCIPAL_COBA)
VALUES (2, 1, '7441234567891', 'N');
INSERT INTO PRO_CODIGO_BARRA (ID_CODIGO_BARRA, ID_PRODUCTO, CODIGO_COBA, ES_PRINCIPAL_COBA)
VALUES (3, 2, '7440000111222', 'S');
INSERT INTO PRO_CODIGO_BARRA (ID_CODIGO_BARRA, ID_PRODUCTO, CODIGO_COBA, ES_PRINCIPAL_COBA)
VALUES (4, 3, '7440000222333', 'S');
INSERT INTO PRO_CODIGO_BARRA (ID_CODIGO_BARRA, ID_PRODUCTO, CODIGO_COBA, ES_PRINCIPAL_COBA)
VALUES (5, 4, '7440000333444', 'S');
INSERT INTO PRO_CODIGO_BARRA (ID_CODIGO_BARRA, ID_PRODUCTO, CODIGO_COBA, ES_PRINCIPAL_COBA)
VALUES (6, 6, '7440000444555', 'S');
INSERT INTO PRO_CODIGO_BARRA (ID_CODIGO_BARRA, ID_PRODUCTO, CODIGO_COBA, ES_PRINCIPAL_COBA)
VALUES (7, 7, '7440000555666', 'S');
INSERT INTO PRO_CODIGO_BARRA (ID_CODIGO_BARRA, ID_PRODUCTO, CODIGO_COBA, ES_PRINCIPAL_COBA)
VALUES (8, 8, '7440000666777', 'S');

-- PRO_PRODUCTO_SUCURSAL (12 registros)
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (1, 1, 1, 25, 10);
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (2, 1, 2, 22, 8);
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (3, 1, 3, 28, 10);
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (4, 1, 4, 20, 5);
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (5, 1, 5, 30, 12);
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (6, 2, 1, 20, 8);
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (7, 3, 1, 15, 5);
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (8, 4, 1, 15, 5);
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (9, 5, 1, 25, 10);
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (10, 6, 1, 25, 10);
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (11, 7, 1, 27, 10);
INSERT INTO PRO_PRODUCTO_SUCURSAL (ID_PRODUCTO_SUCURSAL, ID_PRODUCTO, ID_SUCURSAL, PORC_UTILIDAD_PRSU, PORC_DESC_MAX_PRSU)
VALUES (12, 8, 1, 30, 12);

-- PRO_PRECIO_HIST (5 registros)
INSERT INTO PRO_PRECIO_HIST (ID_PRECIO_HIST, ID_PRODUCTO, COSTO_ANTERIOR_PRHI, FECHA_CAMBIO_PRHI, MOTIVO_PRHI)
VALUES (1, 1, 420, TO_TIMESTAMP('2026-06-01 08:00:00','YYYY-MM-DD HH24:MI:SS'), 'Ajuste por incremento del proveedor');
INSERT INTO PRO_PRECIO_HIST (ID_PRECIO_HIST, ID_PRODUCTO, COSTO_ANTERIOR_PRHI, FECHA_CAMBIO_PRHI, MOTIVO_PRHI)
VALUES (2, 2, 480, TO_TIMESTAMP('2026-06-01 08:05:00','YYYY-MM-DD HH24:MI:SS'), 'Incremento estacional de leche');
INSERT INTO PRO_PRECIO_HIST (ID_PRECIO_HIST, ID_PRODUCTO, COSTO_ANTERIOR_PRHI, FECHA_CAMBIO_PRHI, MOTIVO_PRHI)
VALUES (3, 3, 600, TO_TIMESTAMP('2026-07-01 09:00:00','YYYY-MM-DD HH24:MI:SS'), 'Incremento de flete del proveedor');
INSERT INTO PRO_PRECIO_HIST (ID_PRECIO_HIST, ID_PRODUCTO, COSTO_ANTERIOR_PRHI, FECHA_CAMBIO_PRHI, MOTIVO_PRHI)
VALUES (4, 6, 2600, TO_TIMESTAMP('2026-07-15 10:00:00','YYYY-MM-DD HH24:MI:SS'), 'Ajuste de precio de carne de res');
INSERT INTO PRO_PRECIO_HIST (ID_PRECIO_HIST, ID_PRODUCTO, COSTO_ANTERIOR_PRHI, FECHA_CAMBIO_PRHI, MOTIVO_PRHI)
VALUES (5, 7, 520, TO_TIMESTAMP('2026-08-01 11:00:00','YYYY-MM-DD HH24:MI:SS'), 'Renegociacion con Limpieza Zeta');

-- PRO_LOTE (5 registros)
INSERT INTO PRO_LOTE (ID_LOTE, ID_PRODUCTO, NUMERO_LOTE, FECHA_INGRESO_LOTE, FECHA_VENCIM_LOTE)
VALUES (1, 1, 'L2026-001', TO_DATE('2026-08-01','YYYY-MM-DD'), TO_DATE('2027-02-01','YYYY-MM-DD'));
INSERT INTO PRO_LOTE (ID_LOTE, ID_PRODUCTO, NUMERO_LOTE, FECHA_INGRESO_LOTE, FECHA_VENCIM_LOTE)
VALUES (2, 2, 'L2026-101', TO_DATE('2026-09-01','YYYY-MM-DD'), TO_DATE('2026-09-20','YYYY-MM-DD'));
INSERT INTO PRO_LOTE (ID_LOTE, ID_PRODUCTO, NUMERO_LOTE, FECHA_INGRESO_LOTE, FECHA_VENCIM_LOTE)
VALUES (3, 2, 'L2026-102', TO_DATE('2026-09-05','YYYY-MM-DD'), TO_DATE('2026-09-25','YYYY-MM-DD'));
INSERT INTO PRO_LOTE (ID_LOTE, ID_PRODUCTO, NUMERO_LOTE, FECHA_INGRESO_LOTE, FECHA_VENCIM_LOTE)
VALUES (4, 5, 'L2026-201', TO_DATE('2026-09-08','YYYY-MM-DD'), TO_DATE('2026-09-15','YYYY-MM-DD'));
INSERT INTO PRO_LOTE (ID_LOTE, ID_PRODUCTO, NUMERO_LOTE, FECHA_INGRESO_LOTE, FECHA_VENCIM_LOTE)
VALUES (5, 6, 'L2026-301', TO_DATE('2026-09-01','YYYY-MM-DD'), TO_DATE('2026-12-01','YYYY-MM-DD'));

-- PRO_SERVICIO (5 registros)
INSERT INTO PRO_SERVICIO (ID_SERVICIO, ID_IMPUESTO, CODIGO_SERV, NOMBRE_SERV, PRECIO_SERV)
VALUES (1, 1, 'SERV-0001', 'Envoltura para regalo', 500);
INSERT INTO PRO_SERVICIO (ID_SERVICIO, ID_IMPUESTO, CODIGO_SERV, NOMBRE_SERV, PRECIO_SERV)
VALUES (2, NULL, 'SERV-0002', 'Recarga de telefono celular', 1000);
INSERT INTO PRO_SERVICIO (ID_SERVICIO, ID_IMPUESTO, CODIGO_SERV, NOMBRE_SERV, PRECIO_SERV)
VALUES (3, 1, 'SERV-0003', 'Comision por pago de servicios', 300);
INSERT INTO PRO_SERVICIO (ID_SERVICIO, ID_IMPUESTO, CODIGO_SERV, NOMBRE_SERV, PRECIO_SERV)
VALUES (4, 1, 'SERV-0004', 'Armado de mueble', 5000);
INSERT INTO PRO_SERVICIO (ID_SERVICIO, ID_IMPUESTO, CODIGO_SERV, NOMBRE_SERV, PRECIO_SERV)
VALUES (5, 1, 'SERV-0005', 'Entrega a domicilio', 1500);

-- MODULO INV_ : Bodegas, existencias, movimientos y traslados

-- INV_BODEGA (6 registros)
INSERT INTO INV_BODEGA (ID_BODEGA, ID_SUCURSAL, CODIGO_BODE, NOMBRE_BODE)
VALUES (1, NULL, 'BOD-CEN', 'Bodega Central de la Cadena');
INSERT INTO INV_BODEGA (ID_BODEGA, ID_SUCURSAL, CODIGO_BODE, NOMBRE_BODE)
VALUES (2, 1, 'BOD-PZ01', 'Bodega Super Brunca San Isidro');
INSERT INTO INV_BODEGA (ID_BODEGA, ID_SUCURSAL, CODIGO_BODE, NOMBRE_BODE)
VALUES (3, 2, 'BOD-CT01', 'Bodega Super Brunca Ciudad Neily');
INSERT INTO INV_BODEGA (ID_BODEGA, ID_SUCURSAL, CODIGO_BODE, NOMBRE_BODE)
VALUES (4, 3, 'BOD-GF01', 'Bodega Super Brunca Golfito');
INSERT INTO INV_BODEGA (ID_BODEGA, ID_SUCURSAL, CODIGO_BODE, NOMBRE_BODE)
VALUES (5, 4, 'BOD-BA01', 'Bodega Super Brunca Buenos Aires');
INSERT INTO INV_BODEGA (ID_BODEGA, ID_SUCURSAL, CODIGO_BODE, NOMBRE_BODE)
VALUES (6, 5, 'BOD-SJ01', 'Bodega Super Brunca San Jose');

-- INV_EXISTENCIA (5 registros)
INSERT INTO INV_EXISTENCIA (ID_EXISTENCIA, ID_BODEGA, ID_PRODUCTO, ID_LOTE, CANTIDAD_EXIS)
VALUES (1, 1, 1, 1, 80);
INSERT INTO INV_EXISTENCIA (ID_EXISTENCIA, ID_BODEGA, ID_PRODUCTO, ID_LOTE, CANTIDAD_EXIS)
VALUES (2, 2, 1, 1, 18);
INSERT INTO INV_EXISTENCIA (ID_EXISTENCIA, ID_BODEGA, ID_PRODUCTO, ID_LOTE, CANTIDAD_EXIS)
VALUES (3, 1, 2, 2, 20);
INSERT INTO INV_EXISTENCIA (ID_EXISTENCIA, ID_BODEGA, ID_PRODUCTO, ID_LOTE, CANTIDAD_EXIS)
VALUES (4, 3, 2, 2, 30);
INSERT INTO INV_EXISTENCIA (ID_EXISTENCIA, ID_BODEGA, ID_PRODUCTO, ID_LOTE, CANTIDAD_EXIS)
VALUES (5, 1, 6, 5, 0);

-- INV_MOVIMIENTO (5 registros)
INSERT INTO INV_MOVIMIENTO (ID_MOVIMIENTO, ID_BODEGA, ID_USUARIO, TIPO_MOVI, CONSECUTIVO_MOVI, FECHA_MOVI, DOCUMENTO_REF_MOVI, OBSERVACION_MOVI)
VALUES (1, 1, 2, 'COMPRA', 'MOV-000001', TO_DATE('2026-08-01','YYYY-MM-DD'), 'FC-0001', NULL);
INSERT INTO INV_MOVIMIENTO (ID_MOVIMIENTO, ID_BODEGA, ID_USUARIO, TIPO_MOVI, CONSECUTIVO_MOVI, FECHA_MOVI, DOCUMENTO_REF_MOVI, OBSERVACION_MOVI)
VALUES (2, 1, 2, 'TRASL_SAL', 'MOV-000002', TO_DATE('2026-08-05','YYYY-MM-DD'), 'TRA-000001', NULL);
INSERT INTO INV_MOVIMIENTO (ID_MOVIMIENTO, ID_BODEGA, ID_USUARIO, TIPO_MOVI, CONSECUTIVO_MOVI, FECHA_MOVI, DOCUMENTO_REF_MOVI, OBSERVACION_MOVI)
VALUES (3, 2, 1, 'TRASL_ENT', 'MOV-000003', TO_DATE('2026-08-05','YYYY-MM-DD'), 'TRA-000001', NULL);
INSERT INTO INV_MOVIMIENTO (ID_MOVIMIENTO, ID_BODEGA, ID_USUARIO, TIPO_MOVI, CONSECUTIVO_MOVI, FECHA_MOVI, DOCUMENTO_REF_MOVI, OBSERVACION_MOVI)
VALUES (4, 2, 1, 'VENTA', 'MOV-000004', TO_DATE('2026-09-01','YYYY-MM-DD'), 'FAC-000001', NULL);
INSERT INTO INV_MOVIMIENTO (ID_MOVIMIENTO, ID_BODEGA, ID_USUARIO, TIPO_MOVI, CONSECUTIVO_MOVI, FECHA_MOVI, DOCUMENTO_REF_MOVI, OBSERVACION_MOVI)
VALUES (5, 1, 4, 'AJUSTE_SAL', 'MOV-000005', TO_DATE('2026-09-16','YYYY-MM-DD'), 'AJU-000001', 'Merma por vencimiento de tomate.');

-- INV_MOVIMIENTO_DET (5 registros)
INSERT INTO INV_MOVIMIENTO_DET (ID_MOVIMIENTO_DET, ID_MOVIMIENTO, ID_PRODUCTO, ID_LOTE, LINEA_MODE, CANTIDAD_MODE, COSTO_UNITARIO_MODE)
VALUES (1, 1, 1, 1, 1, 100, 450);
INSERT INTO INV_MOVIMIENTO_DET (ID_MOVIMIENTO_DET, ID_MOVIMIENTO, ID_PRODUCTO, ID_LOTE, LINEA_MODE, CANTIDAD_MODE, COSTO_UNITARIO_MODE)
VALUES (2, 2, 1, 1, 1, 20, 450);
INSERT INTO INV_MOVIMIENTO_DET (ID_MOVIMIENTO_DET, ID_MOVIMIENTO, ID_PRODUCTO, ID_LOTE, LINEA_MODE, CANTIDAD_MODE, COSTO_UNITARIO_MODE)
VALUES (3, 3, 1, 1, 1, 20, 450);
INSERT INTO INV_MOVIMIENTO_DET (ID_MOVIMIENTO_DET, ID_MOVIMIENTO, ID_PRODUCTO, ID_LOTE, LINEA_MODE, CANTIDAD_MODE, COSTO_UNITARIO_MODE)
VALUES (4, 4, 1, 1, 1, 2, 450);
INSERT INTO INV_MOVIMIENTO_DET (ID_MOVIMIENTO_DET, ID_MOVIMIENTO, ID_PRODUCTO, ID_LOTE, LINEA_MODE, CANTIDAD_MODE, COSTO_UNITARIO_MODE)
VALUES (5, 5, 5, 4, 1, 3, 380);

-- INV_TRASLADO (5 registros)
INSERT INTO INV_TRASLADO (ID_TRASLADO, ID_BODEGA_ORIGEN, ID_BODEGA_DESTINO, ID_USUARIO_ENVIA, ID_USUARIO_RECIBE, CONSECUTIVO_TRAS, FECHA_ENVIO_TRAS, FECHA_RECEPCION_TRAS, ESTADO_TRAS)
VALUES (1, 1, 2, 2, 1, 'TRA-000001', TO_DATE('2026-08-05','YYYY-MM-DD'), TO_DATE('2026-08-05','YYYY-MM-DD'), 'R');
INSERT INTO INV_TRASLADO (ID_TRASLADO, ID_BODEGA_ORIGEN, ID_BODEGA_DESTINO, ID_USUARIO_ENVIA, ID_USUARIO_RECIBE, CONSECUTIVO_TRAS, FECHA_ENVIO_TRAS, FECHA_RECEPCION_TRAS, ESTADO_TRAS)
VALUES (2, 1, 3, 2, 3, 'TRA-000002', TO_DATE('2026-08-06','YYYY-MM-DD'), TO_DATE('2026-08-07','YYYY-MM-DD'), 'R');
INSERT INTO INV_TRASLADO (ID_TRASLADO, ID_BODEGA_ORIGEN, ID_BODEGA_DESTINO, ID_USUARIO_ENVIA, ID_USUARIO_RECIBE, CONSECUTIVO_TRAS, FECHA_ENVIO_TRAS, FECHA_RECEPCION_TRAS, ESTADO_TRAS)
VALUES (3, 1, 4, 2, NULL, 'TRA-000003', TO_DATE('2026-08-10','YYYY-MM-DD'), NULL, 'T');
INSERT INTO INV_TRASLADO (ID_TRASLADO, ID_BODEGA_ORIGEN, ID_BODEGA_DESTINO, ID_USUARIO_ENVIA, ID_USUARIO_RECIBE, CONSECUTIVO_TRAS, FECHA_ENVIO_TRAS, FECHA_RECEPCION_TRAS, ESTADO_TRAS)
VALUES (4, 1, 5, 2, NULL, 'TRA-000004', TO_DATE('2026-08-12','YYYY-MM-DD'), NULL, 'P');
INSERT INTO INV_TRASLADO (ID_TRASLADO, ID_BODEGA_ORIGEN, ID_BODEGA_DESTINO, ID_USUARIO_ENVIA, ID_USUARIO_RECIBE, CONSECUTIVO_TRAS, FECHA_ENVIO_TRAS, FECHA_RECEPCION_TRAS, ESTADO_TRAS)
VALUES (5, 1, 6, 2, NULL, 'TRA-000005', TO_DATE('2026-08-14','YYYY-MM-DD'), NULL, 'P');

-- INV_TRASLADO_DET (5 registros)
INSERT INTO INV_TRASLADO_DET (ID_TRASLADO_DET, ID_TRASLADO, ID_PRODUCTO, ID_LOTE, LINEA_TRDE, CANTIDAD_ENVIA_TRDE, CANTIDAD_RECIBE_TRDE)
VALUES (1, 1, 1, 1, 1, 20, 20);
INSERT INTO INV_TRASLADO_DET (ID_TRASLADO_DET, ID_TRASLADO, ID_PRODUCTO, ID_LOTE, LINEA_TRDE, CANTIDAD_ENVIA_TRDE, CANTIDAD_RECIBE_TRDE)
VALUES (2, 2, 2, 2, 1, 30, 30);
INSERT INTO INV_TRASLADO_DET (ID_TRASLADO_DET, ID_TRASLADO, ID_PRODUCTO, ID_LOTE, LINEA_TRDE, CANTIDAD_ENVIA_TRDE, CANTIDAD_RECIBE_TRDE)
VALUES (3, 3, 3, NULL, 1, 40, NULL);
INSERT INTO INV_TRASLADO_DET (ID_TRASLADO_DET, ID_TRASLADO, ID_PRODUCTO, ID_LOTE, LINEA_TRDE, CANTIDAD_ENVIA_TRDE, CANTIDAD_RECIBE_TRDE)
VALUES (4, 4, 6, 5, 1, 15, NULL);
INSERT INTO INV_TRASLADO_DET (ID_TRASLADO_DET, ID_TRASLADO, ID_PRODUCTO, ID_LOTE, LINEA_TRDE, CANTIDAD_ENVIA_TRDE, CANTIDAD_RECIBE_TRDE)
VALUES (5, 5, 7, NULL, 1, 25, NULL);

-- MODULO COM_ : Compras, cuentas por pagar y devoluciones a proveedores

-- COM_FACTURA_COMPRA (7 registros)
INSERT INTO COM_FACTURA_COMPRA (ID_FACTURA_COMPRA, ID_PROVEEDOR, ID_BODEGA, ID_USUARIO, NUM_FACTURA_FACO, FECHA_FACO, ES_CREDITO_FACO, FECHA_VENCIM_FACO, SUBTOTAL_FACO, DESCUENTO_FACO, IMPUESTO_FACO)
VALUES (1, 1, 1, 2, 'FC-0001', TO_DATE('2026-08-01','YYYY-MM-DD'), 'N', NULL, 45000, 0, 5850);
INSERT INTO COM_FACTURA_COMPRA (ID_FACTURA_COMPRA, ID_PROVEEDOR, ID_BODEGA, ID_USUARIO, NUM_FACTURA_FACO, FECHA_FACO, ES_CREDITO_FACO, FECHA_VENCIM_FACO, SUBTOTAL_FACO, DESCUENTO_FACO, IMPUESTO_FACO)
VALUES (2, 2, 1, 2, 'FC-0002', TO_DATE('2026-08-15','YYYY-MM-DD'), 'S', TO_DATE('2026-09-15','YYYY-MM-DD'), 26000, 0, 3380);
INSERT INTO COM_FACTURA_COMPRA (ID_FACTURA_COMPRA, ID_PROVEEDOR, ID_BODEGA, ID_USUARIO, NUM_FACTURA_FACO, FECHA_FACO, ES_CREDITO_FACO, FECHA_VENCIM_FACO, SUBTOTAL_FACO, DESCUENTO_FACO, IMPUESTO_FACO)
VALUES (3, 3, 1, 2, 'FC-0003', TO_DATE('2026-08-20','YYYY-MM-DD'), 'S', TO_DATE('2026-09-05','YYYY-MM-DD'), 13500, 0, 135);
INSERT INTO COM_FACTURA_COMPRA (ID_FACTURA_COMPRA, ID_PROVEEDOR, ID_BODEGA, ID_USUARIO, NUM_FACTURA_FACO, FECHA_FACO, ES_CREDITO_FACO, FECHA_VENCIM_FACO, SUBTOTAL_FACO, DESCUENTO_FACO, IMPUESTO_FACO)
VALUES (4, 4, 1, 2, 'FC-0004', TO_DATE('2026-08-22','YYYY-MM-DD'), 'N', NULL, 17700, 0, 2301);
INSERT INTO COM_FACTURA_COMPRA (ID_FACTURA_COMPRA, ID_PROVEEDOR, ID_BODEGA, ID_USUARIO, NUM_FACTURA_FACO, FECHA_FACO, ES_CREDITO_FACO, FECHA_VENCIM_FACO, SUBTOTAL_FACO, DESCUENTO_FACO, IMPUESTO_FACO)
VALUES (5, 5, 1, 2, 'FC-0005', TO_DATE('2026-08-25','YYYY-MM-DD'), 'S', TO_DATE('2026-09-10','YYYY-MM-DD'), 42000, 0, 5460);
INSERT INTO COM_FACTURA_COMPRA (ID_FACTURA_COMPRA, ID_PROVEEDOR, ID_BODEGA, ID_USUARIO, NUM_FACTURA_FACO, FECHA_FACO, ES_CREDITO_FACO, FECHA_VENCIM_FACO, SUBTOTAL_FACO, DESCUENTO_FACO, IMPUESTO_FACO)
VALUES (6, 1, 1, 2, 'FC-0006', TO_DATE('2026-08-28','YYYY-MM-DD'), 'S', TO_DATE('2026-09-28','YYYY-MM-DD'), 20000, 0, 2600);
INSERT INTO COM_FACTURA_COMPRA (ID_FACTURA_COMPRA, ID_PROVEEDOR, ID_BODEGA, ID_USUARIO, NUM_FACTURA_FACO, FECHA_FACO, ES_CREDITO_FACO, FECHA_VENCIM_FACO, SUBTOTAL_FACO, DESCUENTO_FACO, IMPUESTO_FACO)
VALUES (7, 2, 1, 2, 'FC-0007', TO_DATE('2026-08-29','YYYY-MM-DD'), 'S', TO_DATE('2026-09-29','YYYY-MM-DD'), 15000, 0, 1950);

-- COM_FACTURA_COMPRA_DET (7 registros)
INSERT INTO COM_FACTURA_COMPRA_DET (ID_FACTURA_COMPRA_DET, ID_FACTURA_COMPRA, ID_PRODUCTO, ID_LOTE, LINEA_FCDE, CANTIDAD_FCDE, COSTO_UNITARIO_FCDE, PORC_IMPUESTO_FCDE)
VALUES (1, 1, 1, 1, 1, 100, 450, 13);
INSERT INTO COM_FACTURA_COMPRA_DET (ID_FACTURA_COMPRA_DET, ID_FACTURA_COMPRA, ID_PRODUCTO, ID_LOTE, LINEA_FCDE, CANTIDAD_FCDE, COSTO_UNITARIO_FCDE, PORC_IMPUESTO_FCDE)
VALUES (2, 2, 2, 2, 1, 50, 520, 13);
INSERT INTO COM_FACTURA_COMPRA_DET (ID_FACTURA_COMPRA_DET, ID_FACTURA_COMPRA, ID_PRODUCTO, ID_LOTE, LINEA_FCDE, CANTIDAD_FCDE, COSTO_UNITARIO_FCDE, PORC_IMPUESTO_FCDE)
VALUES (3, 3, 3, NULL, 1, 20, 675, 1);
INSERT INTO COM_FACTURA_COMPRA_DET (ID_FACTURA_COMPRA_DET, ID_FACTURA_COMPRA, ID_PRODUCTO, ID_LOTE, LINEA_FCDE, CANTIDAD_FCDE, COSTO_UNITARIO_FCDE, PORC_IMPUESTO_FCDE)
VALUES (4, 4, 7, NULL, 1, 30, 590, 13);
INSERT INTO COM_FACTURA_COMPRA_DET (ID_FACTURA_COMPRA_DET, ID_FACTURA_COMPRA, ID_PRODUCTO, ID_LOTE, LINEA_FCDE, CANTIDAD_FCDE, COSTO_UNITARIO_FCDE, PORC_IMPUESTO_FCDE)
VALUES (5, 5, 6, 5, 1, 15, 2800, 13);
INSERT INTO COM_FACTURA_COMPRA_DET (ID_FACTURA_COMPRA_DET, ID_FACTURA_COMPRA, ID_PRODUCTO, ID_LOTE, LINEA_FCDE, CANTIDAD_FCDE, COSTO_UNITARIO_FCDE, PORC_IMPUESTO_FCDE)
VALUES (6, 6, 1, NULL, 1, 40, 500, 13);
INSERT INTO COM_FACTURA_COMPRA_DET (ID_FACTURA_COMPRA_DET, ID_FACTURA_COMPRA, ID_PRODUCTO, ID_LOTE, LINEA_FCDE, CANTIDAD_FCDE, COSTO_UNITARIO_FCDE, PORC_IMPUESTO_FCDE)
VALUES (7, 7, 2, NULL, 1, 30, 500, 13);

-- COM_ABONO_PAGAR (5 registros)
INSERT INTO COM_ABONO_PAGAR (ID_ABONO_PAGAR, ID_FACTURA_COMPRA, ID_USUARIO, NUM_COMPROBANTE_ABPA, FECHA_ABPA, MONTO_ABPA)
VALUES (1, 3, 5, 'PAGO-0001', TO_DATE('2026-09-01','YYYY-MM-DD'), 8000);
INSERT INTO COM_ABONO_PAGAR (ID_ABONO_PAGAR, ID_FACTURA_COMPRA, ID_USUARIO, NUM_COMPROBANTE_ABPA, FECHA_ABPA, MONTO_ABPA)
VALUES (2, 6, 5, 'PAGO-0002', TO_DATE('2026-09-10','YYYY-MM-DD'), 10000);
INSERT INTO COM_ABONO_PAGAR (ID_ABONO_PAGAR, ID_FACTURA_COMPRA, ID_USUARIO, NUM_COMPROBANTE_ABPA, FECHA_ABPA, MONTO_ABPA)
VALUES (3, 6, 5, 'PAGO-0003', TO_DATE('2026-09-20','YYYY-MM-DD'), 12600);
INSERT INTO COM_ABONO_PAGAR (ID_ABONO_PAGAR, ID_FACTURA_COMPRA, ID_USUARIO, NUM_COMPROBANTE_ABPA, FECHA_ABPA, MONTO_ABPA)
VALUES (4, 2, 5, 'PAGO-0004', TO_DATE('2026-09-05','YYYY-MM-DD'), 10000);
INSERT INTO COM_ABONO_PAGAR (ID_ABONO_PAGAR, ID_FACTURA_COMPRA, ID_USUARIO, NUM_COMPROBANTE_ABPA, FECHA_ABPA, MONTO_ABPA)
VALUES (5, 7, 5, 'PAGO-0005', TO_DATE('2026-09-02','YYYY-MM-DD'), 5000);

-- COM_DEVOLUCION (5 registros)
INSERT INTO COM_DEVOLUCION (ID_DEVOLUCION_COMPRA, ID_FACTURA_COMPRA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVC, FECHA_DEVC, MOTIVO_DEVC)
VALUES (1, 1, 1, 2, 'DEVC-000001', TO_DATE('2026-08-11','YYYY-MM-DD'), 'Producto con empaque danado detectado en recepcion.');
INSERT INTO COM_DEVOLUCION (ID_DEVOLUCION_COMPRA, ID_FACTURA_COMPRA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVC, FECHA_DEVC, MOTIVO_DEVC)
VALUES (2, 5, 1, 2, 'DEVC-000002', TO_DATE('2026-08-31','YYYY-MM-DD'), 'Carne con fecha de vencimiento cumplida.');
INSERT INTO COM_DEVOLUCION (ID_DEVOLUCION_COMPRA, ID_FACTURA_COMPRA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVC, FECHA_DEVC, MOTIVO_DEVC)
VALUES (3, 4, 1, 2, 'DEVC-000003', TO_DATE('2026-08-25','YYYY-MM-DD'), 'Detergente con empaque roto.');
INSERT INTO COM_DEVOLUCION (ID_DEVOLUCION_COMPRA, ID_FACTURA_COMPRA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVC, FECHA_DEVC, MOTIVO_DEVC)
VALUES (4, 2, 1, 2, 'DEVC-000004', TO_DATE('2026-08-19','YYYY-MM-DD'), 'Leche proxima a vencer, se devuelve parte del lote.');
INSERT INTO COM_DEVOLUCION (ID_DEVOLUCION_COMPRA, ID_FACTURA_COMPRA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVC, FECHA_DEVC, MOTIVO_DEVC)
VALUES (5, 3, 1, 2, 'DEVC-000005', TO_DATE('2026-08-26','YYYY-MM-DD'), 'Arroz con presencia de humedad.');

-- COM_DEVOLUCION_DET (5 registros)
INSERT INTO COM_DEVOLUCION_DET (ID_DEVOLUCION_COMPRA_DET, ID_DEVOLUCION_COMPRA, ID_FACTURA_COMPRA_DET, CANTIDAD_DVCD)
VALUES (1, 1, 1, 10);
INSERT INTO COM_DEVOLUCION_DET (ID_DEVOLUCION_COMPRA_DET, ID_DEVOLUCION_COMPRA, ID_FACTURA_COMPRA_DET, CANTIDAD_DVCD)
VALUES (2, 2, 5, 1.5);
INSERT INTO COM_DEVOLUCION_DET (ID_DEVOLUCION_COMPRA_DET, ID_DEVOLUCION_COMPRA, ID_FACTURA_COMPRA_DET, CANTIDAD_DVCD)
VALUES (3, 3, 4, 3);
INSERT INTO COM_DEVOLUCION_DET (ID_DEVOLUCION_COMPRA_DET, ID_DEVOLUCION_COMPRA, ID_FACTURA_COMPRA_DET, CANTIDAD_DVCD)
VALUES (4, 4, 2, 5);
INSERT INTO COM_DEVOLUCION_DET (ID_DEVOLUCION_COMPRA_DET, ID_DEVOLUCION_COMPRA, ID_FACTURA_COMPRA_DET, CANTIDAD_DVCD)
VALUES (5, 5, 3, 2);

-- COM_NOTA_CREDITO (5 registros)
INSERT INTO COM_NOTA_CREDITO (ID_NOTA_CREDITO_COMPRA, ID_DEVOLUCION_COMPRA, ID_USUARIO, NUM_NOTA_NCCO, FECHA_NCCO, ESTADO_NCCO)
VALUES (1, 1, 2, 'NC-0001', TO_DATE('2026-08-11','YYYY-MM-DD'), 'A');
INSERT INTO COM_NOTA_CREDITO (ID_NOTA_CREDITO_COMPRA, ID_DEVOLUCION_COMPRA, ID_USUARIO, NUM_NOTA_NCCO, FECHA_NCCO, ESTADO_NCCO)
VALUES (2, 5, 2, 'NC-0002', TO_DATE('2026-08-26','YYYY-MM-DD'), 'C');
INSERT INTO COM_NOTA_CREDITO (ID_NOTA_CREDITO_COMPRA, ID_DEVOLUCION_COMPRA, ID_USUARIO, NUM_NOTA_NCCO, FECHA_NCCO, ESTADO_NCCO)
VALUES (3, 2, 2, 'NC-0003', TO_DATE('2026-08-31','YYYY-MM-DD'), 'A');
INSERT INTO COM_NOTA_CREDITO (ID_NOTA_CREDITO_COMPRA, ID_DEVOLUCION_COMPRA, ID_USUARIO, NUM_NOTA_NCCO, FECHA_NCCO, ESTADO_NCCO)
VALUES (4, 3, 2, 'NC-0004', TO_DATE('2026-08-25','YYYY-MM-DD'), 'A');
INSERT INTO COM_NOTA_CREDITO (ID_NOTA_CREDITO_COMPRA, ID_DEVOLUCION_COMPRA, ID_USUARIO, NUM_NOTA_NCCO, FECHA_NCCO, ESTADO_NCCO)
VALUES (5, 4, 2, 'NC-0005', TO_DATE('2026-08-19','YYYY-MM-DD'), 'A');

-- MODULO VEN_ : Facturacion, pagos, cuentas por cobrar y devoluciones de clientes

-- VEN_FACTURA (9 registros)
INSERT INTO VEN_FACTURA (ID_FACTURA_VENTA, ID_CLIENTE, ID_SUCURSAL, ID_USUARIO, NUM_FACTURA_FAVE, FECHA_FAVE, ES_CREDITO_FAVE, FECHA_VENCIM_FAVE, SUBTOTAL_FAVE, DESCUENTO_FAVE, IMPUESTO_FAVE)
VALUES (1, 1, 1, 1, 'FAC-000001', TO_DATE('2026-09-01','YYYY-MM-DD'), 'N', NULL, 5000, 0, 650);
INSERT INTO VEN_FACTURA (ID_FACTURA_VENTA, ID_CLIENTE, ID_SUCURSAL, ID_USUARIO, NUM_FACTURA_FAVE, FECHA_FAVE, ES_CREDITO_FAVE, FECHA_VENCIM_FAVE, SUBTOTAL_FAVE, DESCUENTO_FAVE, IMPUESTO_FAVE)
VALUES (2, 2, 1, 1, 'FAC-000002', TO_DATE('2026-09-02','YYYY-MM-DD'), 'N', NULL, 12000, 1200, 1404);
INSERT INTO VEN_FACTURA (ID_FACTURA_VENTA, ID_CLIENTE, ID_SUCURSAL, ID_USUARIO, NUM_FACTURA_FAVE, FECHA_FAVE, ES_CREDITO_FAVE, FECHA_VENCIM_FAVE, SUBTOTAL_FAVE, DESCUENTO_FAVE, IMPUESTO_FAVE)
VALUES (3, 3, 2, 3, 'FAC-000003', TO_DATE('2026-09-03','YYYY-MM-DD'), 'S', TO_DATE('2026-10-03','YYYY-MM-DD'), 35000, 0, 4550);
INSERT INTO VEN_FACTURA (ID_FACTURA_VENTA, ID_CLIENTE, ID_SUCURSAL, ID_USUARIO, NUM_FACTURA_FAVE, FECHA_FAVE, ES_CREDITO_FAVE, FECHA_VENCIM_FAVE, SUBTOTAL_FAVE, DESCUENTO_FAVE, IMPUESTO_FAVE)
VALUES (4, 4, 3, 4, 'FAC-000004', TO_DATE('2026-09-04','YYYY-MM-DD'), 'N', NULL, 8000, 0, 80);
INSERT INTO VEN_FACTURA (ID_FACTURA_VENTA, ID_CLIENTE, ID_SUCURSAL, ID_USUARIO, NUM_FACTURA_FAVE, FECHA_FAVE, ES_CREDITO_FAVE, FECHA_VENCIM_FAVE, SUBTOTAL_FAVE, DESCUENTO_FAVE, IMPUESTO_FAVE)
VALUES (5, 5, 1, 1, 'FAC-000005', TO_DATE('2026-09-05','YYYY-MM-DD'), 'S', TO_DATE('2026-10-05','YYYY-MM-DD'), 60000, 3000, 7410);
INSERT INTO VEN_FACTURA (ID_FACTURA_VENTA, ID_CLIENTE, ID_SUCURSAL, ID_USUARIO, NUM_FACTURA_FAVE, FECHA_FAVE, ES_CREDITO_FAVE, FECHA_VENCIM_FAVE, SUBTOTAL_FAVE, DESCUENTO_FAVE, IMPUESTO_FAVE)
VALUES (6, 1, 2, 3, 'FAC-000006', TO_DATE('2026-09-05','YYYY-MM-DD'), 'N', NULL, 5000, 0, 650);
INSERT INTO VEN_FACTURA (ID_FACTURA_VENTA, ID_CLIENTE, ID_SUCURSAL, ID_USUARIO, NUM_FACTURA_FAVE, FECHA_FAVE, ES_CREDITO_FAVE, FECHA_VENCIM_FAVE, SUBTOTAL_FAVE, DESCUENTO_FAVE, IMPUESTO_FAVE)
VALUES (7, 3, 2, 3, 'FAC-000007', TO_DATE('2026-09-06','YYYY-MM-DD'), 'S', TO_DATE('2026-10-06','YYYY-MM-DD'), 15000, 0, 1950);
INSERT INTO VEN_FACTURA (ID_FACTURA_VENTA, ID_CLIENTE, ID_SUCURSAL, ID_USUARIO, NUM_FACTURA_FAVE, FECHA_FAVE, ES_CREDITO_FAVE, FECHA_VENCIM_FAVE, SUBTOTAL_FAVE, DESCUENTO_FAVE, IMPUESTO_FAVE)
VALUES (8, 5, 1, 1, 'FAC-000008', TO_DATE('2026-09-07','YYYY-MM-DD'), 'S', TO_DATE('2026-10-07','YYYY-MM-DD'), 80000, 4000, 9880);
INSERT INTO VEN_FACTURA (ID_FACTURA_VENTA, ID_CLIENTE, ID_SUCURSAL, ID_USUARIO, NUM_FACTURA_FAVE, FECHA_FAVE, ES_CREDITO_FAVE, FECHA_VENCIM_FAVE, SUBTOTAL_FAVE, DESCUENTO_FAVE, IMPUESTO_FAVE)
VALUES (9, 5, 1, 1, 'FAC-000009', TO_DATE('2026-09-10','YYYY-MM-DD'), 'S', TO_DATE('2026-10-10','YYYY-MM-DD'), 25000, 0, 3250);

-- VEN_FACTURA_DET (9 registros)
INSERT INTO VEN_FACTURA_DET (ID_FACTURA_VENTA_DET, ID_FACTURA_VENTA, ID_PRODUCTO, ID_SERVICIO, ID_LOTE, LINEA_FVDE, CANTIDAD_FVDE, PRECIO_UNITARIO_FVDE, PORC_DESCUENTO_FVDE, PORC_IMPUESTO_FVDE)
VALUES (1, 1, 1, NULL, NULL, 1, 10, 500, 0, 13);
INSERT INTO VEN_FACTURA_DET (ID_FACTURA_VENTA_DET, ID_FACTURA_VENTA, ID_PRODUCTO, ID_SERVICIO, ID_LOTE, LINEA_FVDE, CANTIDAD_FVDE, PRECIO_UNITARIO_FVDE, PORC_DESCUENTO_FVDE, PORC_IMPUESTO_FVDE)
VALUES (2, 2, 2, NULL, 2, 1, 20, 600, 10, 13);
INSERT INTO VEN_FACTURA_DET (ID_FACTURA_VENTA_DET, ID_FACTURA_VENTA, ID_PRODUCTO, ID_SERVICIO, ID_LOTE, LINEA_FVDE, CANTIDAD_FVDE, PRECIO_UNITARIO_FVDE, PORC_DESCUENTO_FVDE, PORC_IMPUESTO_FVDE)
VALUES (3, 3, 6, NULL, 5, 1, 10, 3500, 0, 13);
INSERT INTO VEN_FACTURA_DET (ID_FACTURA_VENTA_DET, ID_FACTURA_VENTA, ID_PRODUCTO, ID_SERVICIO, ID_LOTE, LINEA_FVDE, CANTIDAD_FVDE, PRECIO_UNITARIO_FVDE, PORC_DESCUENTO_FVDE, PORC_IMPUESTO_FVDE)
VALUES (4, 4, 3, NULL, NULL, 1, 40, 200, 0, 1);
INSERT INTO VEN_FACTURA_DET (ID_FACTURA_VENTA_DET, ID_FACTURA_VENTA, ID_PRODUCTO, ID_SERVICIO, ID_LOTE, LINEA_FVDE, CANTIDAD_FVDE, PRECIO_UNITARIO_FVDE, PORC_DESCUENTO_FVDE, PORC_IMPUESTO_FVDE)
VALUES (5, 5, 7, NULL, NULL, 1, 80, 750, 5, 13);
INSERT INTO VEN_FACTURA_DET (ID_FACTURA_VENTA_DET, ID_FACTURA_VENTA, ID_PRODUCTO, ID_SERVICIO, ID_LOTE, LINEA_FVDE, CANTIDAD_FVDE, PRECIO_UNITARIO_FVDE, PORC_DESCUENTO_FVDE, PORC_IMPUESTO_FVDE)
VALUES (6, 6, NULL, 4, NULL, 1, 1, 5000, 0, 13);
INSERT INTO VEN_FACTURA_DET (ID_FACTURA_VENTA_DET, ID_FACTURA_VENTA, ID_PRODUCTO, ID_SERVICIO, ID_LOTE, LINEA_FVDE, CANTIDAD_FVDE, PRECIO_UNITARIO_FVDE, PORC_DESCUENTO_FVDE, PORC_IMPUESTO_FVDE)
VALUES (7, 7, 2, NULL, NULL, 1, 25, 600, 0, 13);
INSERT INTO VEN_FACTURA_DET (ID_FACTURA_VENTA_DET, ID_FACTURA_VENTA, ID_PRODUCTO, ID_SERVICIO, ID_LOTE, LINEA_FVDE, CANTIDAD_FVDE, PRECIO_UNITARIO_FVDE, PORC_DESCUENTO_FVDE, PORC_IMPUESTO_FVDE)
VALUES (8, 8, 1, NULL, NULL, 1, 160, 500, 5, 13);
INSERT INTO VEN_FACTURA_DET (ID_FACTURA_VENTA_DET, ID_FACTURA_VENTA, ID_PRODUCTO, ID_SERVICIO, ID_LOTE, LINEA_FVDE, CANTIDAD_FVDE, PRECIO_UNITARIO_FVDE, PORC_DESCUENTO_FVDE, PORC_IMPUESTO_FVDE)
VALUES (9, 9, 1, NULL, NULL, 1, 50, 500, 0, 13);

-- VEN_PAGO (5 registros)
INSERT INTO VEN_PAGO (ID_PAGO, ID_FACTURA_VENTA, TIPO_PAGO, LINEA_PAGO, MONTO_PAGO, MONTO_VUELTO_PAGO, REFERENCIA_PAGO)
VALUES (1, 1, 'EFECTIVO', 1, 6000, 350, NULL);
INSERT INTO VEN_PAGO (ID_PAGO, ID_FACTURA_VENTA, TIPO_PAGO, LINEA_PAGO, MONTO_PAGO, MONTO_VUELTO_PAGO, REFERENCIA_PAGO)
VALUES (2, 2, 'TARJETA', 1, 12204, 0, 'AUT-004521');
INSERT INTO VEN_PAGO (ID_PAGO, ID_FACTURA_VENTA, TIPO_PAGO, LINEA_PAGO, MONTO_PAGO, MONTO_VUELTO_PAGO, REFERENCIA_PAGO)
VALUES (3, 4, 'SINPE', 1, 8080, 0, 'SINPE-0099821');
INSERT INTO VEN_PAGO (ID_PAGO, ID_FACTURA_VENTA, TIPO_PAGO, LINEA_PAGO, MONTO_PAGO, MONTO_VUELTO_PAGO, REFERENCIA_PAGO)
VALUES (4, 6, 'EFECTIVO', 1, 3000, 0, NULL);
INSERT INTO VEN_PAGO (ID_PAGO, ID_FACTURA_VENTA, TIPO_PAGO, LINEA_PAGO, MONTO_PAGO, MONTO_VUELTO_PAGO, REFERENCIA_PAGO)
VALUES (5, 6, 'TARJETA', 2, 2650, 0, 'AUT-009981');

-- VEN_ABONO_COBRAR (5 registros)
INSERT INTO VEN_ABONO_COBRAR (ID_ABONO_COBRAR, ID_FACTURA_VENTA, ID_USUARIO, TIPO_PAGO_ABCO, NUM_RECIBO_ABCO, FECHA_ABCO, MONTO_ABCO, REFERENCIA_ABCO)
VALUES (1, 5, 1, 'TARJETA', 'REC-0001', TO_DATE('2026-09-15','YYYY-MM-DD'), 30000, 'AUT-011204');
INSERT INTO VEN_ABONO_COBRAR (ID_ABONO_COBRAR, ID_FACTURA_VENTA, ID_USUARIO, TIPO_PAGO_ABCO, NUM_RECIBO_ABCO, FECHA_ABCO, MONTO_ABCO, REFERENCIA_ABCO)
VALUES (2, 8, 1, 'TRANSFERENCIA', 'REC-0002', TO_DATE('2026-09-18','YYYY-MM-DD'), 50000, 'TRF-20260918-01');
INSERT INTO VEN_ABONO_COBRAR (ID_ABONO_COBRAR, ID_FACTURA_VENTA, ID_USUARIO, TIPO_PAGO_ABCO, NUM_RECIBO_ABCO, FECHA_ABCO, MONTO_ABCO, REFERENCIA_ABCO)
VALUES (3, 8, 1, 'TRANSFERENCIA', 'REC-0003', TO_DATE('2026-09-25','YYYY-MM-DD'), 35880, 'TRF-20260925-01');
INSERT INTO VEN_ABONO_COBRAR (ID_ABONO_COBRAR, ID_FACTURA_VENTA, ID_USUARIO, TIPO_PAGO_ABCO, NUM_RECIBO_ABCO, FECHA_ABCO, MONTO_ABCO, REFERENCIA_ABCO)
VALUES (4, 3, 3, 'EFECTIVO', 'REC-0004', TO_DATE('2026-09-20','YYYY-MM-DD'), 10000, NULL);
INSERT INTO VEN_ABONO_COBRAR (ID_ABONO_COBRAR, ID_FACTURA_VENTA, ID_USUARIO, TIPO_PAGO_ABCO, NUM_RECIBO_ABCO, FECHA_ABCO, MONTO_ABCO, REFERENCIA_ABCO)
VALUES (5, 7, 3, 'SINPE', 'REC-0005', TO_DATE('2026-09-12','YYYY-MM-DD'), 5000, 'SINPE-0104477');

-- VEN_DEVOLUCION (5 registros)
INSERT INTO VEN_DEVOLUCION (ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVV, FECHA_DEVV, MOTIVO_DEVV)
VALUES (1, 2, 2, 1, 'DEVV-000001', TO_DATE('2026-09-03','YYYY-MM-DD'), 'Cliente devolvio parte de la leche por sabor.');
INSERT INTO VEN_DEVOLUCION (ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVV, FECHA_DEVV, MOTIVO_DEVV)
VALUES (2, 1, 2, 1, 'DEVV-000002', TO_DATE('2026-09-02','YYYY-MM-DD'), 'Cambio de producto solicitado por el cliente.');
INSERT INTO VEN_DEVOLUCION (ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVV, FECHA_DEVV, MOTIVO_DEVV)
VALUES (3, 3, 3, 3, 'DEVV-000003', TO_DATE('2026-09-04','YYYY-MM-DD'), 'Carne con atraso de entrega, cliente acepta credito.');
INSERT INTO VEN_DEVOLUCION (ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVV, FECHA_DEVV, MOTIVO_DEVV)
VALUES (4, 8, 2, 1, 'DEVV-000004', TO_DATE('2026-09-08','YYYY-MM-DD'), 'Producto incorrecto entregado al cliente.');
INSERT INTO VEN_DEVOLUCION (ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVV, FECHA_DEVV, MOTIVO_DEVV)
VALUES (5, 9, 2, 1, 'DEVV-000005', TO_DATE('2026-09-11','YYYY-MM-DD'), 'Producto no correspondia a lo solicitado.');

-- VEN_DEVOLUCION_DET (5 registros)
INSERT INTO VEN_DEVOLUCION_DET (ID_DEVOLUCION_VENTA_DET, ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA_DET, CANTIDAD_DVVD)
VALUES (1, 1, 2, 2);
INSERT INTO VEN_DEVOLUCION_DET (ID_DEVOLUCION_VENTA_DET, ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA_DET, CANTIDAD_DVVD)
VALUES (2, 2, 1, 1);
INSERT INTO VEN_DEVOLUCION_DET (ID_DEVOLUCION_VENTA_DET, ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA_DET, CANTIDAD_DVVD)
VALUES (3, 3, 3, 1);
INSERT INTO VEN_DEVOLUCION_DET (ID_DEVOLUCION_VENTA_DET, ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA_DET, CANTIDAD_DVVD)
VALUES (4, 4, 8, 16);
INSERT INTO VEN_DEVOLUCION_DET (ID_DEVOLUCION_VENTA_DET, ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA_DET, CANTIDAD_DVVD)
VALUES (5, 5, 9, 5);

-- VEN_NOTA_CREDITO (5 registros)
INSERT INTO VEN_NOTA_CREDITO (ID_NOTA_CREDITO_VENTA, ID_DEVOLUCION_VENTA, ID_USUARIO, NUM_NOTA_NCVE, FECHA_NCVE, ESTADO_NCVE)
VALUES (1, 1, 1, 'NCV-0001', TO_DATE('2026-09-03','YYYY-MM-DD'), 'A');
INSERT INTO VEN_NOTA_CREDITO (ID_NOTA_CREDITO_VENTA, ID_DEVOLUCION_VENTA, ID_USUARIO, NUM_NOTA_NCVE, FECHA_NCVE, ESTADO_NCVE)
VALUES (2, 2, 1, 'NCV-0002', TO_DATE('2026-09-02','YYYY-MM-DD'), 'C');
INSERT INTO VEN_NOTA_CREDITO (ID_NOTA_CREDITO_VENTA, ID_DEVOLUCION_VENTA, ID_USUARIO, NUM_NOTA_NCVE, FECHA_NCVE, ESTADO_NCVE)
VALUES (3, 3, 3, 'NCV-0003', TO_DATE('2026-09-04','YYYY-MM-DD'), 'A');
INSERT INTO VEN_NOTA_CREDITO (ID_NOTA_CREDITO_VENTA, ID_DEVOLUCION_VENTA, ID_USUARIO, NUM_NOTA_NCVE, FECHA_NCVE, ESTADO_NCVE)
VALUES (4, 4, 1, 'NCV-0004', TO_DATE('2026-09-08','YYYY-MM-DD'), 'A');
INSERT INTO VEN_NOTA_CREDITO (ID_NOTA_CREDITO_VENTA, ID_DEVOLUCION_VENTA, ID_USUARIO, NUM_NOTA_NCVE, FECHA_NCVE, ESTADO_NCVE)
VALUES (5, 5, 1, 'NCV-0005', TO_DATE('2026-09-11','YYYY-MM-DD'), 'A');

-- MODULO PRM_ : Promociones, premios y descuentos

-- PRM_PROMOCION (5 registros)
INSERT INTO PRM_PROMOCION (ID_PROMOCION, ID_SUCURSAL, CODIGO_PROM, NOMBRE_PROM, FECHA_INICIO_PROM, FECHA_FIN_PROM, ESTADO_PROM)
VALUES (1, NULL, 'PROM-0001', 'Lleva 2 lleva 3 en bebidas', TO_DATE('2026-08-01','YYYY-MM-DD'), TO_DATE('2026-08-31','YYYY-MM-DD'), 'F');
INSERT INTO PRM_PROMOCION (ID_PROMOCION, ID_SUCURSAL, CODIGO_PROM, NOMBRE_PROM, FECHA_INICIO_PROM, FECHA_FIN_PROM, ESTADO_PROM)
VALUES (2, NULL, 'PROM-0002', 'Acumula millas Super Brunca', TO_DATE('2026-09-01','YYYY-MM-DD'), TO_DATE('2026-12-31','YYYY-MM-DD'), 'A');
INSERT INTO PRM_PROMOCION (ID_PROMOCION, ID_SUCURSAL, CODIGO_PROM, NOMBRE_PROM, FECHA_INICIO_PROM, FECHA_FIN_PROM, ESTADO_PROM)
VALUES (3, 1, 'PROM-0003', 'Promocion aniversario San Isidro', TO_DATE('2026-09-01','YYYY-MM-DD'), TO_DATE('2026-09-30','YYYY-MM-DD'), 'A');
INSERT INTO PRM_PROMOCION (ID_PROMOCION, ID_SUCURSAL, CODIGO_PROM, NOMBRE_PROM, FECHA_INICIO_PROM, FECHA_FIN_PROM, ESTADO_PROM)
VALUES (4, NULL, 'PROM-0004', 'Temporada de limpieza', TO_DATE('2026-09-15','YYYY-MM-DD'), TO_DATE('2026-10-15','YYYY-MM-DD'), 'A');
INSERT INTO PRM_PROMOCION (ID_PROMOCION, ID_SUCURSAL, CODIGO_PROM, NOMBRE_PROM, FECHA_INICIO_PROM, FECHA_FIN_PROM, ESTADO_PROM)
VALUES (5, NULL, 'PROM-0005', 'Promocion navidena anticipada', TO_DATE('2026-11-01','YYYY-MM-DD'), TO_DATE('2026-12-24','YYYY-MM-DD'), 'I');

-- PRM_PATROCINADOR (5 registros)
INSERT INTO PRM_PATROCINADOR (ID_PATROCINADOR, ID_PROMOCION, ID_PRODUCTO, CANT_REQUERIDA_PATR, ACCIONES_OTORGA_PATR)
VALUES (1, 2, 1, 2, 1);
INSERT INTO PRM_PATROCINADOR (ID_PATROCINADOR, ID_PROMOCION, ID_PRODUCTO, CANT_REQUERIDA_PATR, ACCIONES_OTORGA_PATR)
VALUES (2, 2, 2, 3, 1);
INSERT INTO PRM_PATROCINADOR (ID_PATROCINADOR, ID_PROMOCION, ID_PRODUCTO, CANT_REQUERIDA_PATR, ACCIONES_OTORGA_PATR)
VALUES (3, 2, 6, 1, 2);
INSERT INTO PRM_PATROCINADOR (ID_PATROCINADOR, ID_PROMOCION, ID_PRODUCTO, CANT_REQUERIDA_PATR, ACCIONES_OTORGA_PATR)
VALUES (4, 2, 7, 2, 1);
INSERT INTO PRM_PATROCINADOR (ID_PATROCINADOR, ID_PROMOCION, ID_PRODUCTO, CANT_REQUERIDA_PATR, ACCIONES_OTORGA_PATR)
VALUES (5, 3, 1, 5, 3);

-- PRM_PREMIO (5 registros)
INSERT INTO PRM_PREMIO (ID_PREMIO, ID_PROMOCION, ID_PRODUCTO, NOMBRE_PREM, ACCIONES_COSTO_PREM, CANT_DISPONIBLE_PREM)
VALUES (1, 2, NULL, 'Gorra Super Brunca', 3, 50);
INSERT INTO PRM_PREMIO (ID_PREMIO, ID_PROMOCION, ID_PRODUCTO, NOMBRE_PREM, ACCIONES_COSTO_PREM, CANT_DISPONIBLE_PREM)
VALUES (2, 2, NULL, 'Bolso reutilizable', 5, 30);
INSERT INTO PRM_PREMIO (ID_PREMIO, ID_PROMOCION, ID_PRODUCTO, NOMBRE_PREM, ACCIONES_COSTO_PREM, CANT_DISPONIBLE_PREM)
VALUES (3, 2, 2, 'Un litro de leche gratis', 8, 100);
INSERT INTO PRM_PREMIO (ID_PREMIO, ID_PROMOCION, ID_PRODUCTO, NOMBRE_PREM, ACCIONES_COSTO_PREM, CANT_DISPONIBLE_PREM)
VALUES (4, 3, NULL, 'Vale de 5000 colones para la proxima compra', 3, 1000);
INSERT INTO PRM_PREMIO (ID_PREMIO, ID_PROMOCION, ID_PRODUCTO, NOMBRE_PREM, ACCIONES_COSTO_PREM, CANT_DISPONIBLE_PREM)
VALUES (5, 3, NULL, 'Camiseta edicion aniversario', 6, 40);

-- PRM_ACCION_CLIENTE (5 registros)
INSERT INTO PRM_ACCION_CLIENTE (ID_ACCION_CLIENTE, ID_PROMOCION, ID_FACTURA_VENTA, ID_PREMIO, CANT_ACCIONES_ACLI, FECHA_CANJE_ACLI)
VALUES (1, 2, 2, NULL, 2, NULL);
INSERT INTO PRM_ACCION_CLIENTE (ID_ACCION_CLIENTE, ID_PROMOCION, ID_FACTURA_VENTA, ID_PREMIO, CANT_ACCIONES_ACLI, FECHA_CANJE_ACLI)
VALUES (2, 2, 3, 1, 3, TO_DATE('2026-09-03','YYYY-MM-DD'));
INSERT INTO PRM_ACCION_CLIENTE (ID_ACCION_CLIENTE, ID_PROMOCION, ID_FACTURA_VENTA, ID_PREMIO, CANT_ACCIONES_ACLI, FECHA_CANJE_ACLI)
VALUES (3, 3, 1, NULL, 1, NULL);
INSERT INTO PRM_ACCION_CLIENTE (ID_ACCION_CLIENTE, ID_PROMOCION, ID_FACTURA_VENTA, ID_PREMIO, CANT_ACCIONES_ACLI, FECHA_CANJE_ACLI)
VALUES (4, 2, 8, NULL, 5, NULL);
INSERT INTO PRM_ACCION_CLIENTE (ID_ACCION_CLIENTE, ID_PROMOCION, ID_FACTURA_VENTA, ID_PREMIO, CANT_ACCIONES_ACLI, FECHA_CANJE_ACLI)
VALUES (5, 3, 2, NULL, 2, NULL);

-- PRM_DESCUENTO (5 registros)
INSERT INTO PRM_DESCUENTO (ID_DESCUENTO, ID_SUCURSAL, CODIGO_DSCT, NOMBRE_DSCT, PORCENTAJE_DSCT, MONTO_FIJO_DSCT, FECHA_INICIO_DSCT, FECHA_FIN_DSCT, PRIORIDAD_DSCT, ES_ACUMULABLE_DSCT)
VALUES (1, NULL, 'DSCT-0001', 'Descuento por pronta caducidad', 15, 0, TO_DATE('2026-01-01','YYYY-MM-DD'), TO_DATE('2026-12-31','YYYY-MM-DD'), 1, 'N');
INSERT INTO PRM_DESCUENTO (ID_DESCUENTO, ID_SUCURSAL, CODIGO_DSCT, NOMBRE_DSCT, PORCENTAJE_DSCT, MONTO_FIJO_DSCT, FECHA_INICIO_DSCT, FECHA_FIN_DSCT, PRIORIDAD_DSCT, ES_ACUMULABLE_DSCT)
VALUES (2, NULL, 'DSCT-0002', 'Descuento en la familia de lacteos', 8, 0, TO_DATE('2026-01-01','YYYY-MM-DD'), TO_DATE('2026-12-31','YYYY-MM-DD'), 2, 'S');
INSERT INTO PRM_DESCUENTO (ID_DESCUENTO, ID_SUCURSAL, CODIGO_DSCT, NOMBRE_DSCT, PORCENTAJE_DSCT, MONTO_FIJO_DSCT, FECHA_INICIO_DSCT, FECHA_FIN_DSCT, PRIORIDAD_DSCT, ES_ACUMULABLE_DSCT)
VALUES (3, NULL, 'DSCT-0003', 'Descuento en productos de Limpieza Zeta', 5, 0, TO_DATE('2026-06-01','YYYY-MM-DD'), TO_DATE('2026-12-31','YYYY-MM-DD'), 3, 'S');
INSERT INTO PRM_DESCUENTO (ID_DESCUENTO, ID_SUCURSAL, CODIGO_DSCT, NOMBRE_DSCT, PORCENTAJE_DSCT, MONTO_FIJO_DSCT, FECHA_INICIO_DSCT, FECHA_FIN_DSCT, PRIORIDAD_DSCT, ES_ACUMULABLE_DSCT)
VALUES (4, 1, 'DSCT-0004', 'Descuento fijo por inventario antiguo', 0, 500, TO_DATE('2026-08-01','YYYY-MM-DD'), TO_DATE('2026-10-31','YYYY-MM-DD'), 1, 'N');
INSERT INTO PRM_DESCUENTO (ID_DESCUENTO, ID_SUCURSAL, CODIGO_DSCT, NOMBRE_DSCT, PORCENTAJE_DSCT, MONTO_FIJO_DSCT, FECHA_INICIO_DSCT, FECHA_FIN_DSCT, PRIORIDAD_DSCT, ES_ACUMULABLE_DSCT)
VALUES (5, NULL, 'DSCT-0005', 'Descuento en la familia de carnes', 10, 0, TO_DATE('2026-01-01','YYYY-MM-DD'), TO_DATE('2026-12-31','YYYY-MM-DD'), 2, 'N');

-- PRM_DESCUENTO_REGLA (5 registros)
INSERT INTO PRM_DESCUENTO_REGLA (ID_DESCUENTO_REGLA, ID_DESCUENTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, DIAS_INGRESO_DSRE, DIAS_VENCIM_DSRE)
VALUES (1, 1, NULL, NULL, NULL, 5);
INSERT INTO PRM_DESCUENTO_REGLA (ID_DESCUENTO_REGLA, ID_DESCUENTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, DIAS_INGRESO_DSRE, DIAS_VENCIM_DSRE)
VALUES (2, 2, 4, NULL, NULL, NULL);
INSERT INTO PRM_DESCUENTO_REGLA (ID_DESCUENTO_REGLA, ID_DESCUENTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, DIAS_INGRESO_DSRE, DIAS_VENCIM_DSRE)
VALUES (3, 3, NULL, 4, NULL, NULL);
INSERT INTO PRM_DESCUENTO_REGLA (ID_DESCUENTO_REGLA, ID_DESCUENTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, DIAS_INGRESO_DSRE, DIAS_VENCIM_DSRE)
VALUES (4, 4, NULL, NULL, 60, NULL);
INSERT INTO PRM_DESCUENTO_REGLA (ID_DESCUENTO_REGLA, ID_DESCUENTO, ID_FAMILIA_PRODUCTO, ID_PROVEEDOR, DIAS_INGRESO_DSRE, DIAS_VENCIM_DSRE)
VALUES (5, 5, 2, NULL, NULL, NULL);

-- MODULO AUD_ : Bitacora de auditoria

-- AUD_BITACORA (5 registros)
INSERT INTO AUD_BITACORA (ID_BITACORA, ID_USUARIO, ID_SUCURSAL, TABLA_BITA, LLAVE_REGISTRO_BITA, OPERACION_BITA, MODULO_BITA, DESCRIPCION_BITA, DIRECCION_IP_BITA, FECHA_BITA)
VALUES (1, 1, 1, 'VEN_FACTURA', '1', 'INSERT', 'Ventas', 'Se emitio la factura FAC-000001.', '192.168.10.15', TO_TIMESTAMP('2026-09-01 08:15:00','YYYY-MM-DD HH24:MI:SS'));
INSERT INTO AUD_BITACORA (ID_BITACORA, ID_USUARIO, ID_SUCURSAL, TABLA_BITA, LLAVE_REGISTRO_BITA, OPERACION_BITA, MODULO_BITA, DESCRIPCION_BITA, DIRECCION_IP_BITA, FECHA_BITA)
VALUES (2, 3, 2, 'VEN_FACTURA', '3', 'INSERT', 'Ventas', 'Se emitio la factura FAC-000003 a credito.', '192.168.20.11', TO_TIMESTAMP('2026-09-03 10:40:00','YYYY-MM-DD HH24:MI:SS'));
INSERT INTO AUD_BITACORA (ID_BITACORA, ID_USUARIO, ID_SUCURSAL, TABLA_BITA, LLAVE_REGISTRO_BITA, OPERACION_BITA, MODULO_BITA, DESCRIPCION_BITA, DIRECCION_IP_BITA, FECHA_BITA)
VALUES (3, 2, 1, 'PRO_PRODUCTO', '1', 'UPDATE', 'Productos', 'Se actualizo el precio de costo de Coca Cola 2 litros.', '192.168.10.5', TO_TIMESTAMP('2026-06-01 08:00:00','YYYY-MM-DD HH24:MI:SS'));
INSERT INTO AUD_BITACORA (ID_BITACORA, ID_USUARIO, ID_SUCURSAL, TABLA_BITA, LLAVE_REGISTRO_BITA, OPERACION_BITA, MODULO_BITA, DESCRIPCION_BITA, DIRECCION_IP_BITA, FECHA_BITA)
VALUES (4, 1, 1, 'PER_CLIENTE', '5', 'UPDATE', 'Clientes', 'Se incremento el credito de Constructora del Sur.', '192.168.10.15', TO_TIMESTAMP('2026-06-25 09:30:00','YYYY-MM-DD HH24:MI:SS'));
INSERT INTO AUD_BITACORA (ID_BITACORA, ID_USUARIO, ID_SUCURSAL, TABLA_BITA, LLAVE_REGISTRO_BITA, OPERACION_BITA, MODULO_BITA, DESCRIPCION_BITA, DIRECCION_IP_BITA, FECHA_BITA)
VALUES (5, 5, 4, 'SEG_USUARIO', '5', 'LOGIN', 'Seguridad', 'Inicio de sesion exitoso.', '192.168.40.20', TO_TIMESTAMP('2026-09-10 07:05:00','YYYY-MM-DD HH24:MI:SS'));

COMMIT;

-- Realinea cada secuencia por encima del maximo ID insertado.
-- Los subtipos PER_PERSONA_FISICA y PER_PERSONA_JURIDICA heredan su llave de PER_PERSONA,
-- por lo que sus secuencias existen (toda tabla tiene secuencia) pero no generan llaves.
DECLARE
    PROCEDURE realinear(p_seq IN VARCHAR2, p_tabla IN VARCHAR2, p_pk IN VARCHAR2) IS
        v_max NUMBER;
    BEGIN
        EXECUTE IMMEDIATE 'SELECT NVL(MAX(' || p_pk || '), 0) FROM ' || p_tabla INTO v_max;
        EXECUTE IMMEDIATE 'ALTER SEQUENCE ' || p_seq || ' RESTART START WITH ' || (v_max + 1);
    END;
BEGIN
    realinear('SEQ_CAT_PAIS',               'CAT_PAIS',               'ID_PAIS');
    realinear('SEQ_CAT_PROVINCIA',          'CAT_PROVINCIA',          'ID_PROVINCIA');
    realinear('SEQ_CAT_CANTON',             'CAT_CANTON',             'ID_CANTON');
    realinear('SEQ_CAT_DISTRITO',           'CAT_DISTRITO',           'ID_DISTRITO');
    realinear('SEQ_PER_PERSONA',            'PER_PERSONA',            'ID_PERSONA');
    realinear('SEQ_PER_PERSONA_FISICA',     'PER_PERSONA_FISICA',     'ID_PERSONA_FISICA');
    realinear('SEQ_PER_PERSONA_JURIDICA',   'PER_PERSONA_JURIDICA',   'ID_PERSONA_JURIDICA');
    realinear('SEQ_PER_DIRECCION',          'PER_DIRECCION',          'ID_DIRECCION');
    realinear('SEQ_PER_CONTACTO',           'PER_CONTACTO',           'ID_CONTACTO');
    realinear('SEQ_PER_CLIENTE',            'PER_CLIENTE',            'ID_CLIENTE');
    realinear('SEQ_PER_PROVEEDOR',          'PER_PROVEEDOR',          'ID_PROVEEDOR');
    realinear('SEQ_SEG_EMPRESA',            'SEG_EMPRESA',            'ID_EMPRESA');
    realinear('SEQ_SEG_SUCURSAL',           'SEG_SUCURSAL',           'ID_SUCURSAL');
    realinear('SEQ_SEG_USUARIO',            'SEG_USUARIO',            'ID_USUARIO');
    realinear('SEQ_SEG_USUARIO_SUCURSAL',   'SEG_USUARIO_SUCURSAL',   'ID_USUARIO_SUCURSAL');
    realinear('SEQ_PRO_FAMILIA_PRODUCTO',   'PRO_FAMILIA_PRODUCTO',   'ID_FAMILIA_PRODUCTO');
    realinear('SEQ_PRO_IMPUESTO',           'PRO_IMPUESTO',           'ID_IMPUESTO');
    realinear('SEQ_PRO_PRODUCTO',           'PRO_PRODUCTO',           'ID_PRODUCTO');
    realinear('SEQ_PRO_CODIGO_BARRA',       'PRO_CODIGO_BARRA',       'ID_CODIGO_BARRA');
    realinear('SEQ_PRO_PRODUCTO_SUCURSAL',  'PRO_PRODUCTO_SUCURSAL',  'ID_PRODUCTO_SUCURSAL');
    realinear('SEQ_PRO_PRECIO_HIST',        'PRO_PRECIO_HIST',        'ID_PRECIO_HIST');
    realinear('SEQ_PRO_LOTE',               'PRO_LOTE',               'ID_LOTE');
    realinear('SEQ_PRO_SERVICIO',           'PRO_SERVICIO',           'ID_SERVICIO');
    realinear('SEQ_INV_BODEGA',             'INV_BODEGA',             'ID_BODEGA');
    realinear('SEQ_INV_EXISTENCIA',         'INV_EXISTENCIA',         'ID_EXISTENCIA');
    realinear('SEQ_INV_MOVIMIENTO',         'INV_MOVIMIENTO',         'ID_MOVIMIENTO');
    realinear('SEQ_INV_MOVIMIENTO_DET',     'INV_MOVIMIENTO_DET',     'ID_MOVIMIENTO_DET');
    realinear('SEQ_INV_TRASLADO',           'INV_TRASLADO',           'ID_TRASLADO');
    realinear('SEQ_INV_TRASLADO_DET',       'INV_TRASLADO_DET',       'ID_TRASLADO_DET');
    realinear('SEQ_COM_FACTURA_COMPRA',     'COM_FACTURA_COMPRA',     'ID_FACTURA_COMPRA');
    realinear('SEQ_COM_FACTURA_COMPRA_DET',  'COM_FACTURA_COMPRA_DET',  'ID_FACTURA_COMPRA_DET');
    realinear('SEQ_COM_ABONO_PAGAR',        'COM_ABONO_PAGAR',        'ID_ABONO_PAGAR');
    realinear('SEQ_COM_DEVOLUCION',         'COM_DEVOLUCION',         'ID_DEVOLUCION_COMPRA');
    realinear('SEQ_COM_DEVOLUCION_DET',     'COM_DEVOLUCION_DET',     'ID_DEVOLUCION_COMPRA_DET');
    realinear('SEQ_COM_NOTA_CREDITO',       'COM_NOTA_CREDITO',       'ID_NOTA_CREDITO_COMPRA');
    realinear('SEQ_VEN_FACTURA',            'VEN_FACTURA',            'ID_FACTURA_VENTA');
    realinear('SEQ_VEN_FACTURA_DET',        'VEN_FACTURA_DET',        'ID_FACTURA_VENTA_DET');
    realinear('SEQ_VEN_PAGO',               'VEN_PAGO',               'ID_PAGO');
    realinear('SEQ_VEN_ABONO_COBRAR',       'VEN_ABONO_COBRAR',       'ID_ABONO_COBRAR');
    realinear('SEQ_VEN_DEVOLUCION',         'VEN_DEVOLUCION',         'ID_DEVOLUCION_VENTA');
    realinear('SEQ_VEN_DEVOLUCION_DET',     'VEN_DEVOLUCION_DET',     'ID_DEVOLUCION_VENTA_DET');
    realinear('SEQ_VEN_NOTA_CREDITO',       'VEN_NOTA_CREDITO',       'ID_NOTA_CREDITO_VENTA');
    realinear('SEQ_PRM_PROMOCION',          'PRM_PROMOCION',          'ID_PROMOCION');
    realinear('SEQ_PRM_PATROCINADOR',       'PRM_PATROCINADOR',       'ID_PATROCINADOR');
    realinear('SEQ_PRM_PREMIO',             'PRM_PREMIO',             'ID_PREMIO');
    realinear('SEQ_PRM_ACCION_CLIENTE',     'PRM_ACCION_CLIENTE',     'ID_ACCION_CLIENTE');
    realinear('SEQ_PRM_DESCUENTO',          'PRM_DESCUENTO',          'ID_DESCUENTO');
    realinear('SEQ_PRM_DESCUENTO_REGLA',    'PRM_DESCUENTO_REGLA',    'ID_DESCUENTO_REGLA');
    realinear('SEQ_AUD_BITACORA',           'AUD_BITACORA',           'ID_BITACORA');
END;
/

-- Estadisticas del esquema para el optimizador
BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(
        ownname          => 'CADENA_NEG',
        cascade          => TRUE,
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE);
END;
/

PROMPT Datos de prueba cargados: 49 tablas, 292 filas.
PROMPT Secuencias realineadas por encima del maximo ID insertado.


--------------------------------------------------------------------------------
-- VERIFICACION FINAL
--------------------------------------------------------------------------------
SET SERVEROUTPUT ON
SET FEEDBACK OFF

DECLARE
    v_n NUMBER;   -- las variables deben declararse antes de los subprogramas (PLS-00103)
    PROCEDURE chequear(p_nombre IN VARCHAR2, p_obtenido IN NUMBER, p_esperado IN NUMBER) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(
            RPAD(p_nombre, 26) || RPAD(p_obtenido, 8) ||
            CASE WHEN p_obtenido = p_esperado THEN 'OK'
                 ELSE 'esperado ' || p_esperado END);
    END;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== VERIFICACION ===' || CHR(10));
    -- Se consultan las vistas ALL_ filtrando por el esquema, porque el script corre
    -- con un usuario administrador y CURRENT_SCHEMA = CADENA_NEG.
    SELECT COUNT(*) INTO v_n FROM all_tables WHERE owner = 'CADENA_NEG';
    chequear('Tablas', v_n, 49);
    SELECT COUNT(*) INTO v_n FROM all_sequences WHERE sequence_owner = 'CADENA_NEG';
    chequear('Secuencias', v_n, 49);
    SELECT COUNT(*) INTO v_n FROM all_views WHERE owner = 'CADENA_NEG';
    chequear('Vistas', v_n, 6);
    SELECT COUNT(*) INTO v_n FROM all_constraints
     WHERE owner = 'CADENA_NEG' AND constraint_type = 'R';
    chequear('Llaves foraneas', v_n, 91);
    SELECT COUNT(*) INTO v_n FROM all_constraints
     WHERE owner = 'CADENA_NEG' AND constraint_type = 'C' AND generated = 'USER NAME';
    chequear('Restricciones CHECK', v_n, 140);
    SELECT COUNT(*) INTO v_n FROM user_tablespaces WHERE tablespace_name LIKE 'TBS%';
    chequear('Tablespaces', v_n, 3);
    SELECT COUNT(*) INTO v_n FROM all_objects WHERE owner = 'CADENA_NEG' AND status <> 'VALID';
    chequear('Objetos invalidos', v_n, 0);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- Tablas con menos de 5 filas ---');
    FOR t IN (SELECT table_name FROM all_tables WHERE owner = 'CADENA_NEG' ORDER BY table_name) LOOP
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM CADENA_NEG.' || t.table_name INTO v_n;
        IF v_n < 5 THEN
            DBMS_OUTPUT.PUT_LINE('  ' || t.table_name || ': ' || v_n);
        END IF;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Revision completada.');
END;
/

SET FEEDBACK ON

PROMPT
PROMPT Proyecto creado. Esquema: CADENA_NEG
PROMPT
