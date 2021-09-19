-- Create the database with the following script in command line or pgAdmin:

-- CREATE DATABASE HOSPITAL
--     WITH 
--     OWNER = postgres
--     ENCODING = 'UTF8'
--     LC_COLLATE = 'Hungarian_Hungary.1252'
--     LC_CTYPE = 'Hungarian_Hungary.1252'
--     TABLESPACE = pg_default
--     CONNECTION LIMIT = -1;

-- CREATING TABLES
	
CREATE TABLE IF NOT EXISTS PUBLIC.CITY
(
	ID SERIAL
		CONSTRAINT CITY_PKEY
			PRIMARY KEY,
	NAME VARCHAR(50) NOT NULL
);

ALTER TABLE CITY OWNER TO POSTGRES;

CREATE TABLE IF NOT EXISTS PUBLIC.ADDRESS
(
	ID BIGSERIAL
		CONSTRAINT ADDRESS_PKEY
			PRIMARY KEY,
	DOOR_NUMBER SMALLINT,
	FLOOR SMALLINT,
	HOUSE_NUMBER SMALLINT,
	POSTAL_CODE SMALLINT,
	STREET VARCHAR(50),
	CITY_ID INTEGER
		CONSTRAINT FK_ADDRESS_CITY
			REFERENCES CITY
);

ALTER TABLE ADDRESS OWNER TO POSTGRES;

CREATE INDEX IDX_CITY
	ON ADDRESS (CITY_ID);

CREATE TABLE IF NOT EXISTS PUBLIC.FIRST_NAME
(
	ID SERIAL
		CONSTRAINT FIRST_NAME_PKEY
			PRIMARY KEY,
	IS_WOMAN BOOLEAN NOT NULL,
	NAME VARCHAR(50) NOT NULL,
	CONSTRAINT UNIQUENAMEANDSEX
		UNIQUE (NAME, IS_WOMAN)
);

ALTER TABLE FIRST_NAME OWNER TO POSTGRES;

CREATE INDEX IDX_SEX
	ON FIRST_NAME (IS_WOMAN);

CREATE TABLE IF NOT EXISTS PUBLIC.PATIENT
(
	ID BIGSERIAL
		CONSTRAINT PATIENT_PKEY
			PRIMARY KEY,
	DATE_OF_BIRTH DATE NOT NULL,
	DATE_OF_DEATH DATE,
	CHECK (DATE_OF_BIRTH < DATE_OF_DEATH),
	E_MAIL VARCHAR(100),
	IS_WOMAN BOOLEAN NOT NULL,
	LAST_NAME VARCHAR(50) NOT NULL,
	MOTHERS_LAST_NAME VARCHAR(50) NOT NULL,
	TELEPHONE_NUMBER VARCHAR(16),
	ADDRESS_ID BIGINT
		CONSTRAINT FK_PATIENT_ADDRESS
			REFERENCES ADDRESS,
	CITY_OF_BIRTH_ID INTEGER
		CONSTRAINT FK_PATIENT_CITY
			REFERENCES CITY,
	FIRST_NAME_ID INTEGER NOT NULL
		CONSTRAINT FK_PATIENT_FIRST_NAME
			REFERENCES FIRST_NAME,
	MOTHERS_FIRST_NAME_ID INTEGER NOT NULL
		CONSTRAINT FK_PATIENT_MOTHER_FIRST_NAME
			REFERENCES FIRST_NAME
);

ALTER TABLE PATIENT OWNER TO POSTGRES;

CREATE INDEX IDX_NAME
	ON PATIENT (LAST_NAME, FIRST_NAME_ID);

CREATE TABLE IF NOT EXISTS PUBLIC.RELATIONSHIP_QUALITY
(
	ID SERIAL
		CONSTRAINT RELATIONSHIP_QUALITY_PKEY
			PRIMARY KEY,
	NAME VARCHAR(50) NOT NULL
);

ALTER TABLE RELATIONSHIP_QUALITY OWNER TO POSTGRES;

CREATE TABLE IF NOT EXISTS PUBLIC.RELATIONSHIP_TYPE
(
	ID SERIAL
		CONSTRAINT RELATIONSHIP_TYPE_PKEY
			PRIMARY KEY,
	NAME VARCHAR(50) NOT NULL
);

ALTER TABLE RELATIONSHIP_TYPE OWNER TO POSTGRES;

CREATE TABLE IF NOT EXISTS PUBLIC.RELATIONSHIP
(
	ID BIGSERIAL
		CONSTRAINT RELATIONSHIP_PKEY
			PRIMARY KEY,
	CLOSENESS SMALLINT,
	CHECK (CLOSENESS BETWEEN 1 AND 10),
	START_DATE DATE NOT NULL,
	END_DATE DATE,
	CHECK (START_DATE < END_DATE),
	DESTINATION_PATIENT_ID BIGINT NOT NULL
		CONSTRAINT FK_RELATIONSHIP_PATIENT_DEST
			REFERENCES PATIENT,
	QUALITY_ID SMALLINT
		CONSTRAINT FK_RELATIONSHIP_QUALITY
			REFERENCES RELATIONSHIP_QUALITY,
	SOURCE_PATIENT_ID BIGINT NOT NULL
		CONSTRAINT FK_RELATIONSHIP_PATIENT_SOURCE
			REFERENCES PATIENT,
	TYPE_ID SMALLINT NOT NULL
		CONSTRAINT FK_RELATIONSHIP_RELATIONSHIP_TYPE
			REFERENCES RELATIONSHIP_TYPE,
	CONSTRAINT UNIQUEPARENTANDSOURCE
		UNIQUE (SOURCE_PATIENT_ID, DESTINATION_PATIENT_ID, TYPE_ID)
);

ALTER TABLE RELATIONSHIP OWNER TO POSTGRES;

CREATE INDEX IDX_PATIENTS
	ON RELATIONSHIP (SOURCE_PATIENT_ID, DESTINATION_PATIENT_ID);


-- CREATING FUNCTIONS AND TRIGGERS

-- Relations can not start before the birth date of patients.
create function relationship_start_fix() returns trigger
	language plpgsql
as $BODY$
DECLARE birth_date_source DATE;
    DECLARE birth_date_destination DATE;
    DECLARE birth_date_younger DATE;
BEGIN
    SELECT patient.date_of_birth INTO birth_date_source FROM patient WHERE ID = NEW.source_patient_id LIMIT 1;
    SELECT patient.date_of_birth INTO birth_date_destination FROM patient WHERE ID = NEW.destination_patient_id LIMIT 1;
    birth_date_younger = birth_date_source;
    IF date_gt(birth_date_destination, birth_date_younger) THEN
        birth_date_younger = birth_date_destination;
    END IF;
    IF NEW.start_date < birth_date_younger THEN
        RAISE NOTICE 'Given relation start date (%) corrected to birth date of younger patient (%).', NEW.start_date, birth_date_younger;
        NEW.start_date = birth_date_younger;
    END IF;
    RETURN NEW;
END;
$BODY$;

alter function relationship_start_fix() owner to postgres;

create trigger relationship_start_fixer
	before insert
	on relationship
	for each row
	execute procedure relationship_start_fix();

-- Relations can not end after the death of patients.
create function relationship_end_fix() returns trigger
	language plpgsql
as $BODY$
BEGIN
	IF(NEW.date_of_death IS NOT NULL) THEN
		UPDATE relationship SET end_date = NEW.date_of_death WHERE ((source_patient_id = NEW.id OR destination_patient_id = NEW.id) AND (end_date IS NULL OR end_date > NEW.date_of_death));
	END IF;
	RETURN NEW;
END;
$BODY$;

	alter function relationship_end_fix() owner to postgres;

create trigger relationship_end_fixer
	after update
	on patient
	for each row
	execute procedure relationship_end_fix();

create function relationship_self_prevent() returns trigger
	language plpgsql
as $BODY$
BEGIN
    IF (NEW.source_patient_id = NEW.destination_patient_id) THEN
        RAISE EXCEPTION 'Relationships can not have the same patient as source and destination!';
    END IF;
	RETURN NEW;
END;
$BODY$;

alter function relationship_self_prevent() owner to postgres;

create trigger relationship_self_preventer
	before insert
	on relationship
	for each row
	execute procedure relationship_self_prevent();

