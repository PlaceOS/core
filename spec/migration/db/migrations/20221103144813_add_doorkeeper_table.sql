-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model Auth::OAuthApplications
CREATE TABLE IF NOT EXISTS "oauth_applications"(
    id bigint PRIMARY KEY,
    name character varying NOT NULL,
    uid character varying NOT NULL,
    secret character varying NOT NULL,
    redirect_uri text NOT NULL,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    confidential boolean DEFAULT true NOT NULL,
    owner_id text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

CREATE SEQUENCE public.oauth_applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.oauth_applications_id_seq OWNED BY "oauth_applications".id;
ALTER TABLE ONLY "oauth_applications" ALTER COLUMN id SET DEFAULT nextval('public.oauth_applications_id_seq'::regclass);
CREATE UNIQUE INDEX index_oauth_applications_on_uid ON "oauth_applications" USING btree (uid);


CREATE TABLE IF NOT EXISTS "oauth_access_grants" (
    id bigint PRIMARY KEY,
    resource_owner_id bigint NOT NULL,
    application_id bigint NOT NULL,
    token character varying NOT NULL,
    expires_in integer NOT NULL,
    redirect_uri text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    scopes character varying DEFAULT ''::character varying NOT NULL
);

CREATE SEQUENCE public.oauth_access_grants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.oauth_access_grants_id_seq OWNED BY "oauth_access_grants".id;
ALTER TABLE ONLY "oauth_access_grants" ALTER COLUMN id SET DEFAULT nextval('public.oauth_access_grants_id_seq'::regclass);
CREATE INDEX index_oauth_access_grants_on_application_id ON "oauth_access_grants" USING btree (application_id);
CREATE INDEX index_oauth_access_grants_on_resource_owner_id ON "oauth_access_grants" USING btree (resource_owner_id);
CREATE UNIQUE INDEX index_oauth_access_grants_on_token ON "oauth_access_grants" USING btree (token);
ALTER TABLE ONLY "oauth_access_grants"
    ADD CONSTRAINT fk_oauth_access_grants_on_oauth_applications_id FOREIGN KEY (application_id) REFERENCES "oauth_applications"(id);


CREATE TABLE "oauth_access_tokens" (
    id bigint PRIMARY KEY,
    resource_owner_id bigint,
    application_id bigint NOT NULL,
    token character varying NOT NULL,
    refresh_token character varying,
    expires_in integer,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    scopes character varying,
    previous_refresh_token character varying DEFAULT ''::character varying NOT NULL
);

CREATE SEQUENCE public.oauth_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.oauth_access_tokens_id_seq OWNED BY "oauth_access_tokens".id;
ALTER TABLE ONLY "oauth_access_tokens" ALTER COLUMN id SET DEFAULT nextval('public.oauth_access_tokens_id_seq'::regclass);
CREATE INDEX index_oauth_access_tokens_on_application_id ON "oauth_access_tokens" USING btree (application_id);
CREATE UNIQUE INDEX index_oauth_access_tokens_on_refresh_token ON "oauth_access_tokens" USING btree (refresh_token);
CREATE INDEX index_oauth_access_tokens_on_resource_owner_id ON "oauth_access_tokens" USING btree (resource_owner_id);
CREATE UNIQUE INDEX index_oauth_access_tokens_on_token ON "oauth_access_tokens" USING btree (token);
ALTER TABLE ONLY "oauth_access_tokens"
    ADD CONSTRAINT fk_oauth_access_tokens_on_oauth_applications_id FOREIGN KEY (application_id) REFERENCES "oauth_applications"(id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "oauth_applications"
DROP TABLE IF EXISTS "oauth_access_grants"
DROP TABLE IF EXISTS "oauth_access_tokens"