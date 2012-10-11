--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

--
-- Name: sysinfo; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE sysinfo WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';


ALTER DATABASE sysinfo OWNER TO postgres;

\connect sysinfo

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

--
-- Name: plperlu; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: postgres
--

CREATE OR REPLACE PROCEDURAL LANGUAGE plperlu;


ALTER PROCEDURAL LANGUAGE plperlu OWNER TO postgres;

--
-- Name: plpgsql; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: postgres
--

CREATE OR REPLACE PROCEDURAL LANGUAGE plpgsql;


ALTER PROCEDURAL LANGUAGE plpgsql OWNER TO postgres;

SET search_path = public, pg_catalog;

--
-- Name: ip4; Type: SHELL TYPE; Schema: public; Owner: postgres
--

CREATE TYPE ip4;


--
-- Name: ip4_in(cstring); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_in(cstring) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_in';


ALTER FUNCTION public.ip4_in(cstring) OWNER TO postgres;

--
-- Name: ip4_out(ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_out(ip4) RETURNS cstring
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_out';


ALTER FUNCTION public.ip4_out(ip4) OWNER TO postgres;

--
-- Name: ip4_recv(internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_recv(internal) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_recv';


ALTER FUNCTION public.ip4_recv(internal) OWNER TO postgres;

--
-- Name: ip4_send(ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_send(ip4) RETURNS bytea
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_send';


ALTER FUNCTION public.ip4_send(ip4) OWNER TO postgres;

--
-- Name: ip4; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE ip4 (
    INTERNALLENGTH = 4,
    INPUT = ip4_in,
    OUTPUT = ip4_out,
    RECEIVE = ip4_recv,
    SEND = ip4_send,
    ALIGNMENT = int4,
    STORAGE = plain,
    PASSEDBYVALUE
);


ALTER TYPE public.ip4 OWNER TO postgres;

--
-- Name: TYPE ip4; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TYPE ip4 IS 'IPv4 address ''#.#.#.#''';


--
-- Name: ip4r; Type: SHELL TYPE; Schema: public; Owner: postgres
--

CREATE TYPE ip4r;


--
-- Name: ip4r_in(cstring); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_in(cstring) RETURNS ip4r
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_in';


ALTER FUNCTION public.ip4r_in(cstring) OWNER TO postgres;

--
-- Name: ip4r_out(ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_out(ip4r) RETURNS cstring
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_out';


ALTER FUNCTION public.ip4r_out(ip4r) OWNER TO postgres;

--
-- Name: ip4r_recv(internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_recv(internal) RETURNS ip4r
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_recv';


ALTER FUNCTION public.ip4r_recv(internal) OWNER TO postgres;

--
-- Name: ip4r_send(ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_send(ip4r) RETURNS bytea
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_send';


ALTER FUNCTION public.ip4r_send(ip4r) OWNER TO postgres;

--
-- Name: ip4r; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE ip4r (
    INTERNALLENGTH = 8,
    INPUT = ip4r_in,
    OUTPUT = ip4r_out,
    RECEIVE = ip4r_recv,
    SEND = ip4r_send,
    ELEMENT = ip4,
    ALIGNMENT = int4,
    STORAGE = plain
);


ALTER TYPE public.ip4r OWNER TO postgres;

--
-- Name: TYPE ip4r; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TYPE ip4r IS 'IPv4 range ''#.#.#.#-#.#.#.#'' or ''#.#.#.#/#'' or ''#.#.#.#''';


--
-- Name: activity(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION activity() RETURNS SETOF pg_stat_activity
    LANGUAGE sql SECURITY DEFINER
    AS $$                                                                
  SELECT * FROM pg_stat_activity;                                                                                                         
$$;


ALTER FUNCTION public.activity() OWNER TO postgres;

--
-- Name: cidr(ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION cidr(ip4) RETURNS cidr
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_cast_to_cidr';


ALTER FUNCTION public.cidr(ip4) OWNER TO postgres;

--
-- Name: cidr(ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION cidr(ip4r) RETURNS cidr
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_cast_to_cidr';


ALTER FUNCTION public.cidr(ip4r) OWNER TO postgres;

--
-- Name: entity_description_ins(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION entity_description_ins() RETURNS trigger
    LANGUAGE plpgsql
    AS $$                                                                 
  BEGIN                                                                                                                                    
    IF new.host IS NULL THEN                                                                                                               
      RETURN NEW;                                                                                                                          
    END IF;                                                                                                                                
    INSERT INTO description (host) VALUES (NEW.host);                                                                                      
    RETURN NEW;                                                                                                                            
  END;                                                                                                                                     
$$;


ALTER FUNCTION public.entity_description_ins() OWNER TO postgres;

--
-- Name: env_upsert(text, text); Type: FUNCTION; Schema: public; Owner: sysinfo
--

CREATE FUNCTION env_upsert(text, text) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
  DECLARE
    newhost ALIAS for $1;
    newtag ALIAS for $2;
  BEGIN
    LOOP
        UPDATE tags SET tag = newtag, host = newhost WHERE host = newhost and tag ~* 'env.';
        IF found THEN
            RETURN 1;
        END IF;
        BEGIN
            INSERT INTO tags (tag, host, category) VALUES (newtag, newhost, 'sysinfo');
            RETURN 1;
        EXCEPTION WHEN unique_violation THEN
        END;
    END LOOP;
  END;
$_$;


ALTER FUNCTION public.env_upsert(text, text) OWNER TO sysinfo;

--
-- Name: gip4r_compress(internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION gip4r_compress(internal) RETURNS internal
    LANGUAGE c
    AS '$libdir/ip4r', 'gip4r_compress';


ALTER FUNCTION public.gip4r_compress(internal) OWNER TO postgres;

--
-- Name: gip4r_consistent(internal, ip4r, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION gip4r_consistent(internal, ip4r, integer) RETURNS boolean
    LANGUAGE c
    AS '$libdir/ip4r', 'gip4r_consistent';


ALTER FUNCTION public.gip4r_consistent(internal, ip4r, integer) OWNER TO postgres;

--
-- Name: gip4r_decompress(internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION gip4r_decompress(internal) RETURNS internal
    LANGUAGE c
    AS '$libdir/ip4r', 'gip4r_decompress';


ALTER FUNCTION public.gip4r_decompress(internal) OWNER TO postgres;

--
-- Name: gip4r_penalty(internal, internal, internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION gip4r_penalty(internal, internal, internal) RETURNS internal
    LANGUAGE c STRICT
    AS '$libdir/ip4r', 'gip4r_penalty';


ALTER FUNCTION public.gip4r_penalty(internal, internal, internal) OWNER TO postgres;

--
-- Name: gip4r_picksplit(internal, internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION gip4r_picksplit(internal, internal) RETURNS internal
    LANGUAGE c
    AS '$libdir/ip4r', 'gip4r_picksplit';


ALTER FUNCTION public.gip4r_picksplit(internal, internal) OWNER TO postgres;

--
-- Name: gip4r_same(ip4r, ip4r, internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION gip4r_same(ip4r, ip4r, internal) RETURNS internal
    LANGUAGE c
    AS '$libdir/ip4r', 'gip4r_same';


ALTER FUNCTION public.gip4r_same(ip4r, ip4r, internal) OWNER TO postgres;

--
-- Name: gip4r_union(internal, internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION gip4r_union(internal, internal) RETURNS ip4r
    LANGUAGE c
    AS '$libdir/ip4r', 'gip4r_union';


ALTER FUNCTION public.gip4r_union(internal, internal) OWNER TO postgres;

--
-- Name: iface_notify(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION iface_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$                                                                        
  BEGIN                                                                                                                                   
    notify iface;                                                                                                                         
    return NEW;                                                                                                                           
  END;                                                                                                                                    
$$;


ALTER FUNCTION public.iface_notify() OWNER TO postgres;

--
-- Name: ip4(inet); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4(inet) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_cast_from_inet';


ALTER FUNCTION public.ip4(inet) OWNER TO postgres;

--
-- Name: ip4(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4(text) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_cast_from_text';


ALTER FUNCTION public.ip4(text) OWNER TO postgres;

--
-- Name: ip4(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4(bigint) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_cast_from_bigint';


ALTER FUNCTION public.ip4(bigint) OWNER TO postgres;

--
-- Name: ip4(double precision); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4(double precision) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_cast_from_double';


ALTER FUNCTION public.ip4(double precision) OWNER TO postgres;

--
-- Name: ip4_and(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_and(ip4, ip4) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_and';


ALTER FUNCTION public.ip4_and(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4_cmp(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_cmp(ip4, ip4) RETURNS integer
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_cmp';


ALTER FUNCTION public.ip4_cmp(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4_contained_by(ip4, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_contained_by(ip4, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_contained_by';


ALTER FUNCTION public.ip4_contained_by(ip4, ip4r) OWNER TO postgres;

--
-- Name: ip4_contains(ip4r, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_contains(ip4r, ip4) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_contains';


ALTER FUNCTION public.ip4_contains(ip4r, ip4) OWNER TO postgres;

--
-- Name: ip4_eq(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_eq(ip4, ip4) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_eq';


ALTER FUNCTION public.ip4_eq(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4_ge(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_ge(ip4, ip4) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_ge';


ALTER FUNCTION public.ip4_ge(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4_gt(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_gt(ip4, ip4) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_gt';


ALTER FUNCTION public.ip4_gt(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4_le(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_le(ip4, ip4) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_le';


ALTER FUNCTION public.ip4_le(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4_lt(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_lt(ip4, ip4) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_lt';


ALTER FUNCTION public.ip4_lt(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4_minus_bigint(ip4, bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_minus_bigint(ip4, bigint) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_minus_bigint';


ALTER FUNCTION public.ip4_minus_bigint(ip4, bigint) OWNER TO postgres;

--
-- Name: ip4_minus_int(ip4, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_minus_int(ip4, integer) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_minus_int';


ALTER FUNCTION public.ip4_minus_int(ip4, integer) OWNER TO postgres;

--
-- Name: ip4_minus_ip4(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_minus_ip4(ip4, ip4) RETURNS bigint
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_minus_ip4';


ALTER FUNCTION public.ip4_minus_ip4(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4_neq(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_neq(ip4, ip4) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_neq';


ALTER FUNCTION public.ip4_neq(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4_net_lower(ip4, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_net_lower(ip4, integer) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_net_lower';


ALTER FUNCTION public.ip4_net_lower(ip4, integer) OWNER TO postgres;

--
-- Name: ip4_net_upper(ip4, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_net_upper(ip4, integer) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_net_upper';


ALTER FUNCTION public.ip4_net_upper(ip4, integer) OWNER TO postgres;

--
-- Name: ip4_netmask(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_netmask(integer) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_netmask';


ALTER FUNCTION public.ip4_netmask(integer) OWNER TO postgres;

--
-- Name: ip4_not(ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_not(ip4) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_not';


ALTER FUNCTION public.ip4_not(ip4) OWNER TO postgres;

--
-- Name: ip4_or(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_or(ip4, ip4) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_or';


ALTER FUNCTION public.ip4_or(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4_plus_bigint(ip4, bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_plus_bigint(ip4, bigint) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_plus_bigint';


ALTER FUNCTION public.ip4_plus_bigint(ip4, bigint) OWNER TO postgres;

--
-- Name: ip4_plus_int(ip4, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_plus_int(ip4, integer) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_plus_int';


ALTER FUNCTION public.ip4_plus_int(ip4, integer) OWNER TO postgres;

--
-- Name: ip4_xor(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4_xor(ip4, ip4) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_xor';


ALTER FUNCTION public.ip4_xor(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4hash(ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4hash(ip4) RETURNS integer
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4hash';


ALTER FUNCTION public.ip4hash(ip4) OWNER TO postgres;

--
-- Name: ip4r(cidr); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r(cidr) RETURNS ip4r
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_cast_from_cidr';


ALTER FUNCTION public.ip4r(cidr) OWNER TO postgres;

--
-- Name: ip4r(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r(text) RETURNS ip4r
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_cast_from_text';


ALTER FUNCTION public.ip4r(text) OWNER TO postgres;

--
-- Name: ip4r(ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r(ip4) RETURNS ip4r
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_cast_from_ip4';


ALTER FUNCTION public.ip4r(ip4) OWNER TO postgres;

--
-- Name: ip4r(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r(ip4, ip4) RETURNS ip4r
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_from_ip4s';


ALTER FUNCTION public.ip4r(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4r_cmp(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_cmp(ip4r, ip4r) RETURNS integer
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_cmp';


ALTER FUNCTION public.ip4r_cmp(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_contained_by(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_contained_by(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_contained_by';


ALTER FUNCTION public.ip4r_contained_by(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_contained_by_strict(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_contained_by_strict(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_contained_by_strict';


ALTER FUNCTION public.ip4r_contained_by_strict(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_contains(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_contains(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_contains';


ALTER FUNCTION public.ip4r_contains(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_contains_strict(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_contains_strict(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_contains_strict';


ALTER FUNCTION public.ip4r_contains_strict(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_eq(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_eq(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_eq';


ALTER FUNCTION public.ip4r_eq(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_ge(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_ge(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_ge';


ALTER FUNCTION public.ip4r_ge(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_gt(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_gt(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_gt';


ALTER FUNCTION public.ip4r_gt(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_inter(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_inter(ip4r, ip4r) RETURNS ip4r
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_inter';


ALTER FUNCTION public.ip4r_inter(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_le(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_le(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_le';


ALTER FUNCTION public.ip4r_le(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_left_of(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_left_of(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_left_of';


ALTER FUNCTION public.ip4r_left_of(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_left_overlap(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_left_overlap(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_left_overlap';


ALTER FUNCTION public.ip4r_left_overlap(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_lt(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_lt(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_lt';


ALTER FUNCTION public.ip4r_lt(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_neq(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_neq(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_neq';


ALTER FUNCTION public.ip4r_neq(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_net_mask(ip4, ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_net_mask(ip4, ip4) RETURNS ip4r
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_net_mask';


ALTER FUNCTION public.ip4r_net_mask(ip4, ip4) OWNER TO postgres;

--
-- Name: ip4r_net_prefix(ip4, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_net_prefix(ip4, integer) RETURNS ip4r
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_net_prefix';


ALTER FUNCTION public.ip4r_net_prefix(ip4, integer) OWNER TO postgres;

--
-- Name: ip4r_overlaps(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_overlaps(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_overlaps';


ALTER FUNCTION public.ip4r_overlaps(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_right_of(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_right_of(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_right_of';


ALTER FUNCTION public.ip4r_right_of(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_right_overlap(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_right_overlap(ip4r, ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_right_overlap';


ALTER FUNCTION public.ip4r_right_overlap(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4r_size(ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_size(ip4r) RETURNS double precision
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_size';


ALTER FUNCTION public.ip4r_size(ip4r) OWNER TO postgres;

--
-- Name: ip4r_union(ip4r, ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4r_union(ip4r, ip4r) RETURNS ip4r
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_union';


ALTER FUNCTION public.ip4r_union(ip4r, ip4r) OWNER TO postgres;

--
-- Name: ip4rhash(ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ip4rhash(ip4r) RETURNS integer
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4rhash';


ALTER FUNCTION public.ip4rhash(ip4r) OWNER TO postgres;

--
-- Name: is_cidr(ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION is_cidr(ip4r) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_is_cidr';


ALTER FUNCTION public.is_cidr(ip4r) OWNER TO postgres;

--
-- Name: lower(ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION lower(ip4r) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_lower';


ALTER FUNCTION public.lower(ip4r) OWNER TO postgres;

--
-- Name: meta_upsert(); Type: FUNCTION; Schema: public; Owner: sysinfo
--

CREATE FUNCTION meta_upsert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  DECLARE
    new_name text;
    new_table text;
  BEGIN
    LOOP
        UPDATE meta_membership SET seen = 'now()' WHERE meta_name = NEW.meta_name AND meta_table = TG_TABLE_NAME;
        IF found THEN
            RETURN NEW;
        END IF;
        BEGIN
            INSERT INTO meta_membership(meta_name, meta_table) VALUES (NEW.meta_name, TG_TABLE_NAME);
            RETURN NEW;
        EXCEPTION WHEN unique_violation THEN
        END;
    END LOOP;
  END;
$$;


ALTER FUNCTION public.meta_upsert() OWNER TO sysinfo;

--
-- Name: meta_upsert(text, text); Type: FUNCTION; Schema: public; Owner: sysinfo
--

CREATE FUNCTION meta_upsert(tablename text, name text) RETURNS void
    LANGUAGE plpgsql
    AS $$
  BEGIN
    LOOP
        UPDATE meta_membership SET seen = 'now()' WHERE meta_name = name AND meta_table = tablename;
        IF found THEN
            RETURN;
        END IF;
        BEGIN
            INSERT INTO meta_membership(meta_name, meta_table) VALUES (name, tablename);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
        END;
    END LOOP;
  END;
$$;


ALTER FUNCTION public.meta_upsert(tablename text, name text) OWNER TO sysinfo;

--
-- Name: pg_stat_activity(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION pg_stat_activity() RETURNS SETOF pg_stat_activity
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
 rec RECORD;
BEGIN
    -- Author: Tony Wasson (part of nagiosplugins for postgresql)
    -- Overview: Let non super users see query details from pg_stat_activity
    -- Revisions: (when, who, what)
    --   2006-08-29 TW - Checked into CVS after a user request.
    FOR rec IN SELECT * FROM pg_stat_activity
    LOOP
        RETURN NEXT rec;
    END LOOP;
    RETURN;
END;
$$;


ALTER FUNCTION public.pg_stat_activity() OWNER TO postgres;

--
-- Name: pgx_grant(text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION pgx_grant(text, text, text) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
  priv ALIAS FOR $1;
  patt ALIAS FOR $2;
  user ALIAS FOR $3;
  obj  record;
  num  integer;
BEGIN
  num:=0;
  FOR obj IN SELECT relname FROM pg_class 
  WHERE relname LIKE patt || '%' AND relkind in ('r','v','S') LOOP
    EXECUTE 'GRANT ' || priv || ' ON ' || obj.relname || ' TO ' || user;
    num := num + 1;
  END LOOP;
  RETURN num;
END;
$_$;


ALTER FUNCTION public.pgx_grant(text, text, text) OWNER TO postgres;

--
-- Name: plpgsql_call_handler(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION plpgsql_call_handler() RETURNS language_handler
    LANGUAGE c
    AS '$libdir/plpgsql', 'plpgsql_call_handler';


ALTER FUNCTION public.plpgsql_call_handler() OWNER TO postgres;

--
-- Name: status_upsert(text, text); Type: FUNCTION; Schema: public; Owner: sysinfo
--

CREATE FUNCTION status_upsert(text, text) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
  DECLARE
    newhost ALIAS for $1;
    newtag ALIAS for $2;
  BEGIN
    LOOP
        UPDATE tags SET tag = newtag , host = newhost WHERE host = newhost and tag ~* 'status.';
        IF found THEN
            RETURN 1;
        END IF;
        BEGIN
            INSERT INTO tags (tag, host, category) VALUES (newtag, newhost, 'sysinfo');
            RETURN 1;
        EXCEPTION WHEN unique_violation THEN
        END;
    END LOOP;
  END;
$_$;


ALTER FUNCTION public.status_upsert(text, text) OWNER TO sysinfo;

--
-- Name: tag_env_upsert(); Type: FUNCTION; Schema: public; Owner: sysinfo
--

CREATE FUNCTION tag_env_upsert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$                                                                      
  DECLARE                                                                                                                                 
    newtag text;                                                                                                                          
  BEGIN                                                                                                                                   
    IF new.host IS NULL THEN                                                                                                              
      RETURN NEW;                                                                                                                         
    END IF;                                                                                                                               
    IF new.env IS NULL THEN                                                                                                               
      RETURN NEW;                                                                                                                         
    END IF;                                                                                                                               
    LOOP                                                                                                                                  
      newtag = 'env.' || NEW.env;                                                                                                         
      UPDATE tags SET tag = newtag WHERE host = NEW.host and tag ~* 'env.';                                                               
      IF found THEN                                                                                                                       
        RETURN NEW;                                                                                                                       
      END IF;                                                                                                                             
      BEGIN                                                                                                                               
        INSERT INTO tags (tag, host, category) VALUES (newtag, NEW.host, 'sysinfo');                                                      
        RETURN NEW;                                                                                                                       
        EXCEPTION WHEN unique_violation THEN                                                                                              
      END;                                                                                                                                
    END LOOP;                                                                                                                             
  END;                                                                                                                                    
$$;


ALTER FUNCTION public.tag_env_upsert() OWNER TO sysinfo;

--
-- Name: tag_status_upsert(); Type: FUNCTION; Schema: public; Owner: sysinfo
--

CREATE FUNCTION tag_status_upsert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$                                                                   
  DECLARE                                                                                                                                 
    newtag text;                                                                                                                          
  BEGIN                                                                                                                                   
    IF new.host IS NULL THEN                                                                                                              
      RETURN NEW;                                                                                                                         
    END IF;                                                                                                                               
    IF new.status IS NULL THEN                                                                                                            
      RETURN NEW;                                                                                                                         
    END IF;                                                                                                                               
    LOOP                                                                                                                                  
      newtag = 'status.' || NEW.status;                                                                                                   
      UPDATE tags SET tag = newtag WHERE host = NEW.host and tag ~* 'status.';                                                            
      IF found THEN                                                                                                                       
        RETURN NEW;                                                                                                                       
      END IF;                                                                                                                             
      BEGIN                                                                                                                               
        INSERT INTO tags (tag, host, category) VALUES (newtag, NEW.host, 'sysinfo');                                                      
        RETURN NEW;                                                                                                                       
        EXCEPTION WHEN unique_violation THEN                                                                                              
      END;                                                                                                                                
    END LOOP;                                                                                                                             
  END;                                                                                                                                    
$$;


ALTER FUNCTION public.tag_status_upsert() OWNER TO sysinfo;

--
-- Name: text(ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION text(ip4) RETURNS text
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_cast_to_text';


ALTER FUNCTION public.text(ip4) OWNER TO postgres;

--
-- Name: text(ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION text(ip4r) RETURNS text
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_cast_to_text';


ALTER FUNCTION public.text(ip4r) OWNER TO postgres;

--
-- Name: ti_notify(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ti_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$                                                                           
  BEGIN                                                                                                                                   
    notify foo;                                                                                                                           
    return NEW;                                                                                                                           
  END;                                                                                                                                    
$$;


ALTER FUNCTION public.ti_notify() OWNER TO postgres;

--
-- Name: tiface_check(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION tiface_check() RETURNS trigger
    LANGUAGE plpgsql
    AS $$                                                                           
  DECLARE                                                                                                                                 
    newmac text;                                                                                                                          
  BEGIN                                                                                                                                   
    newmac := new.mac::text;                                                                                                              
    IF newmac = '00:00:00:00:00:00' THEN                                                                                                  
      newmac := '00:00:00:00:00:01';                                                                                                      
    END IF;                                                                                                                               
    NEW.mac = newmac::macaddr;                                                                                                            
    return NEW;                                                                                                                           
  END;                                                                                                                                    
$$;


ALTER FUNCTION public.tiface_check() OWNER TO postgres;

--
-- Name: to_bigint(ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION to_bigint(ip4) RETURNS bigint
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_cast_to_bigint';


ALTER FUNCTION public.to_bigint(ip4) OWNER TO postgres;

--
-- Name: to_double(ip4); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION to_double(ip4) RETURNS double precision
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4_cast_to_double';


ALTER FUNCTION public.to_double(ip4) OWNER TO postgres;

--
-- Name: trim_alerts(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION trim_alerts() RETURNS integer
    LANGUAGE plpgsql
    AS $$
  DECLARE
        integer_var integer;
  BEGIN
    DELETE from alerts where last_seen <= (now() - interval '180 days')::timestamp WITHOUT TIME ZONE;
    GET DIAGNOSTICS integer_var = ROW_COUNT;
    RETURN integer_var;
  END
$$;


ALTER FUNCTION public.trim_alerts() OWNER TO postgres;

--
-- Name: trim_hist(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION trim_hist() RETURNS integer
    LANGUAGE plpgsql
    AS $$
  DECLARE
        integer_var integer;
  BEGIN
    DELETE FROM hist where seen < (now() - interval '365 days')::timestamp WITHOUT TIME ZONE;
    GET DIAGNOSTICS integer_var = ROW_COUNT;
    RETURN integer_var;
  END
$$;


ALTER FUNCTION public.trim_hist() OWNER TO postgres;

--
-- Name: trim_history(); Type: FUNCTION; Schema: public; Owner: sysinfo
--

CREATE FUNCTION trim_history() RETURNS integer
    LANGUAGE plpgsql
    AS $$
  DECLARE
        integer_var integer;
  BEGIN
    DELETE from history where last_seen <= (now() - interval '180 days')::timestamp WITHOUT TIME ZONE;
    GET DIAGNOSTICS integer_var = ROW_COUNT;
    RETURN integer_var;
  END
$$;


ALTER FUNCTION public.trim_history() OWNER TO sysinfo;

--
-- Name: trim_netid_range_history(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION trim_netid_range_history() RETURNS integer
    LANGUAGE plpgsql
    AS $$
  DECLARE
        integer_var integer;
  BEGIN 
    DELETE FROM netid_range_history WHERE seen <= (now() - interval '120 days')::timestamp WITHOUT TIME ZONE;
    GET DIAGNOSTICS integer_var = ROW_COUNT;
    RETURN integer_var;
  END
$$;


ALTER FUNCTION public.trim_netid_range_history() OWNER TO postgres;

--
-- Name: upper(ip4r); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION upper(ip4r) RETURNS ip4
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/ip4r', 'ip4r_upper';


ALTER FUNCTION public.upper(ip4r) OWNER TO postgres;

--
-- Name: #; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR # (
    PROCEDURE = ip4_xor,
    LEFTARG = ip4,
    RIGHTARG = ip4
);


ALTER OPERATOR public.# (ip4, ip4) OWNER TO postgres;

--
-- Name: &; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR & (
    PROCEDURE = ip4_and,
    LEFTARG = ip4,
    RIGHTARG = ip4
);


ALTER OPERATOR public.& (ip4, ip4) OWNER TO postgres;

--
-- Name: &&; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR && (
    PROCEDURE = ip4r_overlaps,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = &&,
    RESTRICT = areasel,
    JOIN = areajoinsel
);


ALTER OPERATOR public.&& (ip4r, ip4r) OWNER TO postgres;

--
-- Name: &<<; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR &<< (
    PROCEDURE = ip4r_left_overlap,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    RESTRICT = positionsel,
    JOIN = positionjoinsel
);


ALTER OPERATOR public.&<< (ip4r, ip4r) OWNER TO postgres;

--
-- Name: &>>; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR &>> (
    PROCEDURE = ip4r_right_overlap,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    RESTRICT = positionsel,
    JOIN = positionjoinsel
);


ALTER OPERATOR public.&>> (ip4r, ip4r) OWNER TO postgres;

--
-- Name: +; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR + (
    PROCEDURE = ip4_plus_int,
    LEFTARG = ip4,
    RIGHTARG = integer
);


ALTER OPERATOR public.+ (ip4, integer) OWNER TO postgres;

--
-- Name: +; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR + (
    PROCEDURE = ip4_plus_bigint,
    LEFTARG = ip4,
    RIGHTARG = bigint
);


ALTER OPERATOR public.+ (ip4, bigint) OWNER TO postgres;

--
-- Name: -; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR - (
    PROCEDURE = ip4_minus_int,
    LEFTARG = ip4,
    RIGHTARG = integer
);


ALTER OPERATOR public.- (ip4, integer) OWNER TO postgres;

--
-- Name: -; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR - (
    PROCEDURE = ip4_minus_bigint,
    LEFTARG = ip4,
    RIGHTARG = bigint
);


ALTER OPERATOR public.- (ip4, bigint) OWNER TO postgres;

--
-- Name: -; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR - (
    PROCEDURE = ip4_minus_ip4,
    LEFTARG = ip4,
    RIGHTARG = ip4
);


ALTER OPERATOR public.- (ip4, ip4) OWNER TO postgres;

--
-- Name: <; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR < (
    PROCEDURE = ip4_lt,
    LEFTARG = ip4,
    RIGHTARG = ip4,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel,
    JOIN = scalarltjoinsel
);


ALTER OPERATOR public.< (ip4, ip4) OWNER TO postgres;

--
-- Name: <; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR < (
    PROCEDURE = ip4r_lt,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel,
    JOIN = scalarltjoinsel
);


ALTER OPERATOR public.< (ip4r, ip4r) OWNER TO postgres;

--
-- Name: <<; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR << (
    PROCEDURE = ip4r_contained_by_strict,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = >>,
    RESTRICT = contsel,
    JOIN = contjoinsel
);


ALTER OPERATOR public.<< (ip4r, ip4r) OWNER TO postgres;

--
-- Name: <<<; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR <<< (
    PROCEDURE = ip4r_left_of,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = >>>,
    RESTRICT = positionsel,
    JOIN = positionjoinsel
);


ALTER OPERATOR public.<<< (ip4r, ip4r) OWNER TO postgres;

--
-- Name: <<=; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR <<= (
    PROCEDURE = ip4r_contained_by,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = >>=,
    RESTRICT = contsel,
    JOIN = contjoinsel
);


ALTER OPERATOR public.<<= (ip4r, ip4r) OWNER TO postgres;

--
-- Name: <=; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR <= (
    PROCEDURE = ip4_le,
    LEFTARG = ip4,
    RIGHTARG = ip4,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel,
    JOIN = scalarltjoinsel
);


ALTER OPERATOR public.<= (ip4, ip4) OWNER TO postgres;

--
-- Name: <=; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR <= (
    PROCEDURE = ip4r_le,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel,
    JOIN = scalarltjoinsel
);


ALTER OPERATOR public.<= (ip4r, ip4r) OWNER TO postgres;

--
-- Name: <>; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR <> (
    PROCEDURE = ip4_neq,
    LEFTARG = ip4,
    RIGHTARG = ip4,
    COMMUTATOR = <>,
    NEGATOR = =,
    RESTRICT = neqsel,
    JOIN = neqjoinsel
);


ALTER OPERATOR public.<> (ip4, ip4) OWNER TO postgres;

--
-- Name: <>; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR <> (
    PROCEDURE = ip4r_neq,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = <>,
    NEGATOR = =,
    RESTRICT = neqsel,
    JOIN = neqjoinsel
);


ALTER OPERATOR public.<> (ip4r, ip4r) OWNER TO postgres;

--
-- Name: =; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR = (
    PROCEDURE = ip4_eq,
    LEFTARG = ip4,
    RIGHTARG = ip4,
    COMMUTATOR = =,
    NEGATOR = <>,
    MERGES,
    HASHES,
    RESTRICT = eqsel,
    JOIN = eqjoinsel
);


ALTER OPERATOR public.= (ip4, ip4) OWNER TO postgres;

--
-- Name: =; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR = (
    PROCEDURE = ip4r_eq,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = =,
    NEGATOR = <>,
    MERGES,
    HASHES,
    RESTRICT = eqsel,
    JOIN = eqjoinsel
);


ALTER OPERATOR public.= (ip4r, ip4r) OWNER TO postgres;

--
-- Name: >; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR > (
    PROCEDURE = ip4_gt,
    LEFTARG = ip4,
    RIGHTARG = ip4,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel,
    JOIN = scalargtjoinsel
);


ALTER OPERATOR public.> (ip4, ip4) OWNER TO postgres;

--
-- Name: >; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR > (
    PROCEDURE = ip4r_gt,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel,
    JOIN = scalargtjoinsel
);


ALTER OPERATOR public.> (ip4r, ip4r) OWNER TO postgres;

--
-- Name: >=; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR >= (
    PROCEDURE = ip4_ge,
    LEFTARG = ip4,
    RIGHTARG = ip4,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel,
    JOIN = scalargtjoinsel
);


ALTER OPERATOR public.>= (ip4, ip4) OWNER TO postgres;

--
-- Name: >=; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR >= (
    PROCEDURE = ip4r_ge,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel,
    JOIN = scalargtjoinsel
);


ALTER OPERATOR public.>= (ip4r, ip4r) OWNER TO postgres;

--
-- Name: >>; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR >> (
    PROCEDURE = ip4r_contains_strict,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = <<,
    RESTRICT = contsel,
    JOIN = contjoinsel
);


ALTER OPERATOR public.>> (ip4r, ip4r) OWNER TO postgres;

--
-- Name: >>=; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR >>= (
    PROCEDURE = ip4r_contains,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = <<=,
    RESTRICT = contsel,
    JOIN = contjoinsel
);


ALTER OPERATOR public.>>= (ip4r, ip4r) OWNER TO postgres;

--
-- Name: >>>; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR >>> (
    PROCEDURE = ip4r_right_of,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = <<<,
    RESTRICT = positionsel,
    JOIN = positionjoinsel
);


ALTER OPERATOR public.>>> (ip4r, ip4r) OWNER TO postgres;

--
-- Name: @; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR @ (
    PROCEDURE = ip4r_contains,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = ~,
    RESTRICT = contsel,
    JOIN = contjoinsel
);


ALTER OPERATOR public.@ (ip4r, ip4r) OWNER TO postgres;

--
-- Name: |; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR | (
    PROCEDURE = ip4_or,
    LEFTARG = ip4,
    RIGHTARG = ip4
);


ALTER OPERATOR public.| (ip4, ip4) OWNER TO postgres;

--
-- Name: ~; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR ~ (
    PROCEDURE = ip4_not,
    RIGHTARG = ip4
);


ALTER OPERATOR public.~ (NONE, ip4) OWNER TO postgres;

--
-- Name: ~; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR ~ (
    PROCEDURE = ip4r_contained_by,
    LEFTARG = ip4r,
    RIGHTARG = ip4r,
    COMMUTATOR = @,
    RESTRICT = contsel,
    JOIN = contjoinsel
);


ALTER OPERATOR public.~ (ip4r, ip4r) OWNER TO postgres;

--
-- Name: btree_ip4_ops; Type: OPERATOR CLASS; Schema: public; Owner: postgres
--

CREATE OPERATOR CLASS btree_ip4_ops
    DEFAULT FOR TYPE ip4 USING btree AS
    OPERATOR 1 <(ip4,ip4) ,
    OPERATOR 2 <=(ip4,ip4) ,
    OPERATOR 3 =(ip4,ip4) ,
    OPERATOR 4 >=(ip4,ip4) ,
    OPERATOR 5 >(ip4,ip4) ,
    FUNCTION 1 ip4_cmp(ip4,ip4);


ALTER OPERATOR CLASS public.btree_ip4_ops USING btree OWNER TO postgres;

--
-- Name: btree_ip4r_ops; Type: OPERATOR CLASS; Schema: public; Owner: postgres
--

CREATE OPERATOR CLASS btree_ip4r_ops
    DEFAULT FOR TYPE ip4r USING btree AS
    OPERATOR 1 <(ip4r,ip4r) ,
    OPERATOR 2 <=(ip4r,ip4r) ,
    OPERATOR 3 =(ip4r,ip4r) ,
    OPERATOR 4 >=(ip4r,ip4r) ,
    OPERATOR 5 >(ip4r,ip4r) ,
    FUNCTION 1 ip4r_cmp(ip4r,ip4r);


ALTER OPERATOR CLASS public.btree_ip4r_ops USING btree OWNER TO postgres;

--
-- Name: gist_ip4r_ops; Type: OPERATOR CLASS; Schema: public; Owner: postgres
--

CREATE OPERATOR CLASS gist_ip4r_ops
    DEFAULT FOR TYPE ip4r USING gist AS
    OPERATOR 1 >>=(ip4r,ip4r) ,
    OPERATOR 2 <<=(ip4r,ip4r) ,
    OPERATOR 3 >>(ip4r,ip4r) ,
    OPERATOR 4 <<(ip4r,ip4r) ,
    OPERATOR 5 &&(ip4r,ip4r) ,
    OPERATOR 6 =(ip4r,ip4r) ,
    FUNCTION 1 gip4r_consistent(internal,ip4r,integer) ,
    FUNCTION 2 gip4r_union(internal,internal) ,
    FUNCTION 3 gip4r_compress(internal) ,
    FUNCTION 4 gip4r_decompress(internal) ,
    FUNCTION 5 gip4r_penalty(internal,internal,internal) ,
    FUNCTION 6 gip4r_picksplit(internal,internal) ,
    FUNCTION 7 gip4r_same(ip4r,ip4r,internal);


ALTER OPERATOR CLASS public.gist_ip4r_ops USING gist OWNER TO postgres;

--
-- Name: hash_ip4_ops; Type: OPERATOR CLASS; Schema: public; Owner: postgres
--

CREATE OPERATOR CLASS hash_ip4_ops
    DEFAULT FOR TYPE ip4 USING hash AS
    OPERATOR 1 =(ip4,ip4) ,
    FUNCTION 1 ip4hash(ip4);


ALTER OPERATOR CLASS public.hash_ip4_ops USING hash OWNER TO postgres;

--
-- Name: hash_ip4r_ops; Type: OPERATOR CLASS; Schema: public; Owner: postgres
--

CREATE OPERATOR CLASS hash_ip4r_ops
    DEFAULT FOR TYPE ip4r USING hash AS
    OPERATOR 1 =(ip4r,ip4r) ,
    FUNCTION 1 ip4rhash(ip4r);


ALTER OPERATOR CLASS public.hash_ip4r_ops USING hash OWNER TO postgres;

SET search_path = pg_catalog;

--
-- Name: CAST (cidr AS public.ip4r); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (cidr AS public.ip4r) WITH FUNCTION public.ip4r(cidr) AS ASSIGNMENT;


--
-- Name: CAST (double precision AS public.ip4); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (double precision AS public.ip4) WITH FUNCTION public.ip4(double precision);


--
-- Name: CAST (inet AS public.ip4); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (inet AS public.ip4) WITH FUNCTION public.ip4(inet) AS ASSIGNMENT;


--
-- Name: CAST (bigint AS public.ip4); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (bigint AS public.ip4) WITH FUNCTION public.ip4(bigint);


--
-- Name: CAST (public.ip4 AS cidr); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (public.ip4 AS cidr) WITH FUNCTION public.cidr(public.ip4) AS ASSIGNMENT;


--
-- Name: CAST (public.ip4 AS double precision); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (public.ip4 AS double precision) WITH FUNCTION public.to_double(public.ip4);


--
-- Name: CAST (public.ip4 AS bigint); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (public.ip4 AS bigint) WITH FUNCTION public.to_bigint(public.ip4);


--
-- Name: CAST (public.ip4 AS public.ip4r); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (public.ip4 AS public.ip4r) WITH FUNCTION public.ip4r(public.ip4) AS IMPLICIT;


--
-- Name: CAST (public.ip4 AS text); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (public.ip4 AS text) WITH FUNCTION public.text(public.ip4);


--
-- Name: CAST (public.ip4r AS cidr); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (public.ip4r AS cidr) WITH FUNCTION public.cidr(public.ip4r);


--
-- Name: CAST (public.ip4r AS text); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (public.ip4r AS text) WITH FUNCTION public.text(public.ip4r);


--
-- Name: CAST (text AS public.ip4); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (text AS public.ip4) WITH FUNCTION public.ip4(text);


--
-- Name: CAST (text AS public.ip4r); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (text AS public.ip4r) WITH FUNCTION public.ip4r(text);


SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: alert_settings; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE alert_settings (
    source text NOT NULL,
    category text NOT NULL,
    alert text NOT NULL,
    severity text,
    email text
);


ALTER TABLE public.alert_settings OWNER TO sysinfo;

--
-- Name: alerts_aid_seq; Type: SEQUENCE; Schema: public; Owner: sysinfo
--

CREATE SEQUENCE alerts_aid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.alerts_aid_seq OWNER TO sysinfo;

--
-- Name: alerts; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE alerts (
    aid bigint DEFAULT nextval('alerts_aid_seq'::regclass) NOT NULL,
    host text NOT NULL,
    source text,
    category text,
    alert text,
    count integer,
    first_seen timestamp without time zone,
    last_seen timestamp without time zone DEFAULT now(),
    ack_by text
);


ALTER TABLE public.alerts OWNER TO sysinfo;

--
-- Name: appliance; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE appliance (
    host text NOT NULL,
    vendor text,
    os_version text,
    hardware_id text,
    hardware_desc text,
    seen timestamp without time zone
);


ALTER TABLE public.appliance OWNER TO sysinfo;

--
-- Name: appliance_config; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE appliance_config (
    host text NOT NULL,
    attribute text NOT NULL,
    value text,
    seen timestamp without time zone
);


ALTER TABLE public.appliance_config OWNER TO sysinfo;

--
-- Name: appliance_features; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE appliance_features (
    host text NOT NULL,
    feature text NOT NULL,
    status text,
    seen timestamp without time zone
);


ALTER TABLE public.appliance_features OWNER TO sysinfo;

--
-- Name: appliance_ha; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE appliance_ha (
    host text NOT NULL,
    attribute text NOT NULL,
    value text,
    seen timestamp without time zone
);


ALTER TABLE public.appliance_ha OWNER TO sysinfo;

--
-- Name: appliance_modes; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE appliance_modes (
    host text NOT NULL,
    mode text NOT NULL,
    status text,
    seen timestamp without time zone
);


ALTER TABLE public.appliance_modes OWNER TO sysinfo;

--
-- Name: appliance_status; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE appliance_status (
    host text NOT NULL,
    status text NOT NULL,
    message text,
    seen timestamp without time zone
);


ALTER TABLE public.appliance_status OWNER TO sysinfo;

--
-- Name: arp; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE arp (
    host text NOT NULL,
    remote text,
    mac text,
    seen timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.arp OWNER TO sysinfo;

--
-- Name: arptest; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE arptest (
    host text,
    remote text,
    mac macaddr,
    seen timestamp without time zone
);


ALTER TABLE public.arptest OWNER TO sysinfo;

--
-- Name: asl; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE asl (
    host text NOT NULL,
    version text,
    perl text,
    seen timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.asl OWNER TO sysinfo;

--
-- Name: bigip; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE bigip (
    host text NOT NULL,
    pool text,
    member text,
    status text,
    seen timestamp without time zone
);


ALTER TABLE public.bigip OWNER TO sysinfo;

--
-- Name: bigip_pools; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE bigip_pools (
    host text NOT NULL,
    pool text,
    member text,
    seen timestamp without time zone
);


ALTER TABLE public.bigip_pools OWNER TO sysinfo;

--
-- Name: bios; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE bios (
    host text NOT NULL,
    bios_vendor text,
    bios_version text,
    bios_date text,
    seen timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.bios OWNER TO sysinfo;

--
-- Name: bridge; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE bridge (
    host text NOT NULL,
    bridge text NOT NULL,
    interface text NOT NULL,
    id text,
    stp text,
    seen timestamp without time zone
);


ALTER TABLE public.bridge OWNER TO sysinfo;

--
-- Name: brmac; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE brmac (
    host text NOT NULL,
    bridge text NOT NULL,
    mac macaddr NOT NULL,
    local text NOT NULL,
    seen timestamp without time zone
);


ALTER TABLE public.brmac OWNER TO sysinfo;

--
-- Name: tags; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE tags (
    host text NOT NULL,
    tag text NOT NULL,
    seen timestamp without time zone DEFAULT now() NOT NULL,
    category text NOT NULL,
    multi text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.tags OWNER TO sysinfo;

--
-- Name: campus_devices; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW campus_devices AS
    SELECT tags.host FROM tags WHERE ((tags.tag = 'model.cisco'::text) AND (NOT (tags.host IN (SELECT tags.host FROM tags WHERE (tags.tag = ANY (ARRAY['network.topo.datacenter'::text, 'network.topo.datacenter_departmental'::text, 'network.topo.datacenter_open'::text, 'network.topo.datacenter_secure'::text, 'network.topo.hpc'::text, 'network.topo.ideal'::text, 'network.topo.nasmgt'::text, 'network.topo.noc'::text, 'network.topo.noc_open'::text, 'network.topo.noc_secure'::text, 'network.topo.san'::text, 'network.topo.usi'::text])))))) ORDER BY tags.host;


ALTER TABLE public.campus_devices OWNER TO sysinfo;

--
-- Name: cca; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE cca (
    host text NOT NULL,
    farm_dns text NOT NULL,
    ss_loc text,
    primary_host text,
    failover_host text
);


ALTER TABLE public.cca OWNER TO sysinfo;

--
-- Name: client_functions; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE client_functions (
    host text,
    function text,
    args text,
    seen timestamp without time zone,
    completed timestamp without time zone,
    result text
);


ALTER TABLE public.client_functions OWNER TO sysinfo;

--
-- Name: conf; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE conf (
    host text NOT NULL,
    source text NOT NULL,
    contents text,
    seen timestamp without time zone
);


ALTER TABLE public.conf OWNER TO sysinfo;

--
-- Name: connections; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE connections (
    host text,
    local_addr cidr,
    remote_addr cidr,
    port integer,
    count integer,
    average integer
);


ALTER TABLE public.connections OWNER TO sysinfo;

--
-- Name: cpumem; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE cpumem (
    host text NOT NULL,
    cpu text,
    cpu_speed text,
    cpu_cache text,
    cpu_count smallint,
    mem text,
    seen timestamp without time zone,
    mem_tot text
);


ALTER TABLE public.cpumem OWNER TO sysinfo;

--
-- Name: dell_warranty; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE dell_warranty (
    serial text,
    description text,
    provider text,
    start_date date,
    end_date date
);


ALTER TABLE public.dell_warranty OWNER TO sysinfo;

--
-- Name: description; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE description (
    host text NOT NULL,
    service text,
    group_code text,
    group_name text,
    type text,
    purpose text,
    location text,
    seen timestamp without time zone,
    env text DEFAULT 'prod'::text,
    status text DEFAULT 'active'::text
);


ALTER TABLE public.description OWNER TO sysinfo;

--
-- Name: description_backup; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE description_backup (
    data text,
    seen timestamp without time zone
);


ALTER TABLE public.description_backup OWNER TO sysinfo;

--
-- Name: description_history; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE description_history (
    host text NOT NULL,
    col text NOT NULL,
    val text NOT NULL,
    uid text NOT NULL,
    seen timestamp without time zone NOT NULL
);


ALTER TABLE public.description_history OWNER TO sysinfo;

--
-- Name: device; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE device (
    host text NOT NULL,
    vendor text,
    model text,
    model_type text,
    serial text,
    uuid text,
    seen timestamp without time zone,
    device_type text DEFAULT 'Server'::text
);


ALTER TABLE public.device OWNER TO sysinfo;

--
-- Name: disk; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE disk (
    host text NOT NULL,
    device text NOT NULL,
    vendor text,
    model text,
    rev text,
    serial text,
    size text,
    seen timestamp without time zone
);


ALTER TABLE public.disk OWNER TO sysinfo;

--
-- Name: dns_aliases; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE dns_aliases (
    host text NOT NULL,
    ip text NOT NULL,
    alias text NOT NULL,
    cname text,
    seen timestamp without time zone
);


ALTER TABLE public.dns_aliases OWNER TO sysinfo;

--
-- Name: domain_map; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE domain_map (
    subnet cidr NOT NULL,
    pop text,
    domain text,
    override integer DEFAULT 0,
    creation timestamp without time zone DEFAULT now()
);


ALTER TABLE public.domain_map OWNER TO sysinfo;

--
-- Name: drac_console; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE drac_console (
    host text NOT NULL,
    url text,
    seen timestamp without time zone
);


ALTER TABLE public.drac_console OWNER TO sysinfo;

--
-- Name: drac_device; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE drac_device (
    host text NOT NULL,
    ip text,
    vendor text,
    model text,
    service_tag text,
    serial_number text,
    seen timestamp without time zone
);


ALTER TABLE public.drac_device OWNER TO sysinfo;

--
-- Name: drac_os; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE drac_os (
    host text NOT NULL,
    os text,
    seen timestamp without time zone
);


ALTER TABLE public.drac_os OWNER TO sysinfo;

--
-- Name: save_heartbeat; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE save_heartbeat (
    host text NOT NULL,
    seen timestamp without time zone,
    activity text DEFAULT 'active'::text,
    server_seen timestamp without time zone
);


ALTER TABLE public.save_heartbeat OWNER TO sysinfo;

--
-- Name: drac_system; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW drac_system AS
    SELECT drac_device.host, device.host AS system FROM device, drac_device, save_heartbeat heartbeat WHERE (((heartbeat.host = device.host) AND (heartbeat.activity = 'active'::text)) AND (device.serial = drac_device.service_tag));


ALTER TABLE public.drac_system OWNER TO sysinfo;

--
-- Name: edna_server; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE edna_server (
    host text NOT NULL,
    version text NOT NULL,
    seen timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.edna_server OWNER TO sysinfo;

--
-- Name: entity; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE entity (
    host text NOT NULL,
    type text NOT NULL,
    seen timestamp without time zone DEFAULT now() NOT NULL,
    location text,
    location_type text
);


ALTER TABLE public.entity OWNER TO sysinfo;

--
-- Name: entity_mappings; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE entity_mappings (
    entity_type text NOT NULL,
    component text NOT NULL,
    sort_order integer
);


ALTER TABLE public.entity_mappings OWNER TO sysinfo;

--
-- Name: entity_test; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE entity_test (
    host text,
    type text,
    seen timestamp without time zone
);


ALTER TABLE public.entity_test OWNER TO sysinfo;

--
-- Name: events_eid_seq; Type: SEQUENCE; Schema: public; Owner: sysinfo
--

CREATE SEQUENCE events_eid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.events_eid_seq OWNER TO sysinfo;

--
-- Name: events; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE events (
    event text,
    params text,
    seen timestamp without time zone DEFAULT now(),
    aid bigint,
    eid bigint DEFAULT nextval('events_eid_seq'::regclass) NOT NULL
);


ALTER TABLE public.events OWNER TO sysinfo;

--
-- Name: fiber; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE fiber (
    host text NOT NULL,
    source text,
    contents text,
    seen timestamp without time zone
);


ALTER TABLE public.fiber OWNER TO sysinfo;

--
-- Name: ghetto; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE ghetto (
    host text,
    stuff bigint,
    seen timestamp without time zone
);


ALTER TABLE public.ghetto OWNER TO sysinfo;

--
-- Name: hardware_inventory; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE hardware_inventory (
    serial text NOT NULL,
    property_control text,
    location text
);


ALTER TABLE public.hardware_inventory OWNER TO sysinfo;

--
-- Name: hbtest; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE hbtest (
    host text,
    seen timestamp without time zone,
    active boolean DEFAULT true
);


ALTER TABLE public.hbtest OWNER TO sysinfo;

--
-- Name: server_heartbeats; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE server_heartbeats (
    host text NOT NULL,
    server text NOT NULL,
    source text NOT NULL,
    seen timestamp without time zone,
    server_seen timestamp without time zone
);


ALTER TABLE public.server_heartbeats OWNER TO sysinfo;

--
-- Name: heartbeat; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW heartbeat AS
    SELECT foo.host, foo.seen, foo.server_seen, CASE WHEN (foo.seen > (now() - '1 day'::interval)) THEN 'active'::text ELSE 'inactive'::text END AS activity FROM (SELECT server_heartbeats.host, max(server_heartbeats.seen) AS seen, max(server_heartbeats.server_seen) AS server_seen FROM server_heartbeats GROUP BY server_heartbeats.host) foo;


ALTER TABLE public.heartbeat OWNER TO sysinfo;

--
-- Name: heartbeat2; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW heartbeat2 AS
    SELECT foo.host, foo.seen, foo.server_seen, CASE WHEN (foo.seen > (now() - '1 day'::interval)) THEN 'active'::text ELSE 'inactive'::text END AS activity FROM (SELECT server_heartbeats.host, max(server_heartbeats.seen) AS seen, max(server_heartbeats.server_seen) AS server_seen FROM server_heartbeats GROUP BY server_heartbeats.host) foo;


ALTER TABLE public.heartbeat2 OWNER TO sysinfo;

--
-- Name: heartbeat_asl; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE heartbeat_asl (
    host text NOT NULL,
    source text NOT NULL,
    seen timestamp without time zone
);


ALTER TABLE public.heartbeat_asl OWNER TO sysinfo;

--
-- Name: heartbeat_syslog; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE heartbeat_syslog (
    host text NOT NULL,
    fqdn text NOT NULL,
    loghost text NOT NULL,
    seen timestamp without time zone
);


ALTER TABLE public.heartbeat_syslog OWNER TO sysinfo;

--
-- Name: hist_index_seq; Type: SEQUENCE; Schema: public; Owner: sysinfo
--

CREATE SEQUENCE hist_index_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.hist_index_seq OWNER TO sysinfo;

--
-- Name: hist; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE hist (
    host text NOT NULL,
    tab character varying(128) NOT NULL,
    source character varying(256) NOT NULL,
    data text,
    diff text,
    seen timestamp without time zone NOT NULL,
    index integer DEFAULT nextval('hist_index_seq'::regclass) NOT NULL
);


ALTER TABLE public.hist OWNER TO sysinfo;

--
-- Name: host_passwd; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE host_passwd (
    host text NOT NULL,
    name text NOT NULL,
    passwd text,
    uid text,
    gid text,
    gecos text,
    dir text,
    shell text,
    date_added timestamp without time zone,
    date_removed timestamp without time zone,
    last_login timestamp without time zone
);


ALTER TABLE public.host_passwd OWNER TO sysinfo;

--
-- Name: iface; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE iface (
    host text NOT NULL,
    iface text NOT NULL,
    ip inet,
    mac macaddr,
    speed text,
    duplex text,
    neg text,
    seen timestamp without time zone,
    netmask inet,
    type text,
    port text,
    oper_state text,
    admin_state text
);


ALTER TABLE public.iface OWNER TO sysinfo;

--
-- Name: iface_active; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW iface_active AS
    SELECT iface.host, iface.iface, iface.ip, iface.mac, iface.speed, iface.duplex, iface.neg, iface.seen, iface.netmask FROM iface, save_heartbeat heartbeat WHERE ((iface.host = heartbeat.host) AND (heartbeat.activity = 'active'::text));


ALTER TABLE public.iface_active OWNER TO sysinfo;

--
-- Name: instest; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE instest (
    host text NOT NULL,
    attribute text NOT NULL,
    value text,
    seen timestamp without time zone
);


ALTER TABLE public.instest OWNER TO sysinfo;

--
-- Name: iscsi; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE iscsi (
    host text,
    driver_version text,
    iname text,
    target_name text,
    host_id text,
    bus_id text,
    target_id text,
    target_address inet,
    target_ports text,
    session_status text,
    session_id text,
    seen timestamp without time zone,
    name text,
    target_iname text
);


ALTER TABLE public.iscsi OWNER TO sysinfo;

--
-- Name: iscsi_lun; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE iscsi_lun (
    host text NOT NULL,
    page80 text,
    id text,
    device text,
    vendor text,
    model text,
    seen timestamp without time zone,
    page83_type3 text
);


ALTER TABLE public.iscsi_lun OWNER TO sysinfo;

--
-- Name: listening_ports; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE listening_ports (
    host text NOT NULL,
    addr text NOT NULL,
    port integer NOT NULL,
    seen timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.listening_ports OWNER TO sysinfo;

--
-- Name: lock_test; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE lock_test (
    data text
);


ALTER TABLE public.lock_test OWNER TO sysinfo;

--
-- Name: locktest; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE locktest (
    foo integer NOT NULL
);


ALTER TABLE public.locktest OWNER TO sysinfo;

--
-- Name: md; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE md (
    host text NOT NULL,
    md text NOT NULL,
    devices integer,
    level text,
    chunk text,
    blocks bigint,
    members text,
    seen timestamp without time zone
);


ALTER TABLE public.md OWNER TO sysinfo;

--
-- Name: meta_membership; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE meta_membership (
    meta_name text NOT NULL,
    meta_table text NOT NULL,
    seen timestamp without time zone DEFAULT now()
);


ALTER TABLE public.meta_membership OWNER TO sysinfo;

--
-- Name: meta_web_alias; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE meta_web_alias (
    meta_name text NOT NULL,
    host text NOT NULL,
    address text NOT NULL,
    source text NOT NULL,
    seen timestamp without time zone
);


ALTER TABLE public.meta_web_alias OWNER TO sysinfo;

--
-- Name: meta_web_redirect; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE meta_web_redirect (
    meta_name text NOT NULL,
    host text NOT NULL,
    match text NOT NULL,
    destination text NOT NULL,
    seen timestamp without time zone
);


ALTER TABLE public.meta_web_redirect OWNER TO sysinfo;

--
-- Name: meta_web_vhost; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE meta_web_vhost (
    meta_name text NOT NULL,
    host text NOT NULL,
    port integer NOT NULL,
    doc_root text NOT NULL,
    seen timestamp without time zone DEFAULT now()
);


ALTER TABLE public.meta_web_vhost OWNER TO sysinfo;

--
-- Name: monitor_defs; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE monitor_defs (
    host text NOT NULL,
    toggle text,
    rules text
);


ALTER TABLE public.monitor_defs OWNER TO sysinfo;

--
-- Name: mounts; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE mounts (
    host text,
    dev text,
    mount text,
    type text,
    mount_options text,
    fstab_options text,
    in_fstab boolean,
    in_mount boolean,
    nfs_addr text,
    seen timestamp without time zone
);


ALTER TABLE public.mounts OWNER TO sysinfo;

--
-- Name: netapp_aggregates; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netapp_aggregates (
    host text NOT NULL,
    name text NOT NULL,
    aggr_id integer NOT NULL,
    type text,
    owning_host text,
    status text,
    state text,
    fsid text,
    uuid text,
    options text,
    flexvol_list text,
    seen timestamp without time zone
);


ALTER TABLE public.netapp_aggregates OWNER TO sysinfo;

--
-- Name: netapp_connected_initiators; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netapp_connected_initiators (
    host text NOT NULL,
    portal_group text,
    isid text,
    type text,
    port_name text,
    node_iname text,
    node_name text,
    seen timestamp without time zone
);


ALTER TABLE public.netapp_connected_initiators OWNER TO sysinfo;

--
-- Name: netapp_device; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netapp_device (
    host text NOT NULL,
    vendor text,
    model text,
    serial_number text,
    sys_id text,
    sysname text,
    seen timestamp without time zone
);


ALTER TABLE public.netapp_device OWNER TO sysinfo;

--
-- Name: netapp_df; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netapp_df (
    host text NOT NULL,
    file_sys text NOT NULL,
    mount text,
    type text,
    total_size text,
    status text,
    mirror_status text,
    plex_count integer,
    df_id integer NOT NULL,
    seen timestamp without time zone
);


ALTER TABLE public.netapp_df OWNER TO sysinfo;

--
-- Name: netapp_fcp; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netapp_fcp (
    host text NOT NULL,
    name text NOT NULL,
    type text,
    topology text,
    status text,
    speed text,
    wwnn text,
    wwpn text,
    fcp_id integer NOT NULL,
    seen timestamp without time zone
);


ALTER TABLE public.netapp_fcp OWNER TO sysinfo;

--
-- Name: netapp_features; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netapp_features (
    host text NOT NULL,
    feature text NOT NULL,
    licensed text,
    enabled text,
    seen timestamp without time zone
);


ALTER TABLE public.netapp_features OWNER TO sysinfo;

--
-- Name: netapp_iface; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netapp_iface (
    host text NOT NULL,
    iface text,
    type text,
    port text NOT NULL,
    mac macaddr,
    ip inet,
    netmask inet,
    speed text,
    duplex text,
    oper_state text,
    admin_state text,
    negotiate text,
    seen timestamp without time zone
);


ALTER TABLE public.netapp_iface OWNER TO sysinfo;

--
-- Name: netapp_luns; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netapp_luns (
    host text NOT NULL,
    index text,
    online text,
    snap_status text,
    share_status text,
    name text,
    comment text,
    mapped text,
    serial_number text,
    qtree_name text,
    seen timestamp without time zone
);


ALTER TABLE public.netapp_luns OWNER TO sysinfo;

--
-- Name: netapp_os; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netapp_os (
    host text NOT NULL,
    firmware text,
    cpu_arch text,
    os text,
    seen timestamp without time zone
);


ALTER TABLE public.netapp_os OWNER TO sysinfo;

--
-- Name: netapp_qtrees; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netapp_qtrees (
    host text NOT NULL,
    idx text NOT NULL,
    name text NOT NULL,
    volume integer NOT NULL,
    volume_name text,
    id integer NOT NULL,
    style text,
    status text,
    seen timestamp without time zone
);


ALTER TABLE public.netapp_qtrees OWNER TO sysinfo;

--
-- Name: netapp_volumes; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netapp_volumes (
    host text NOT NULL,
    name text NOT NULL,
    volume_id integer NOT NULL,
    type text,
    owning_host text,
    status text,
    state text,
    fsid text,
    uuid text,
    seen timestamp without time zone,
    vol_aggr_name text
);


ALTER TABLE public.netapp_volumes OWNER TO sysinfo;

--
-- Name: netid_multinet_sid_seq; Type: SEQUENCE; Schema: public; Owner: sysinfo
--

CREATE SEQUENCE netid_multinet_sid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.netid_multinet_sid_seq OWNER TO sysinfo;

--
-- Name: netid_multinet; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netid_multinet (
    multinet bigint NOT NULL,
    first_seen timestamp without time zone,
    last_seen timestamp without time zone,
    sid integer DEFAULT nextval('netid_multinet_sid_seq'::regclass) NOT NULL
);


ALTER TABLE public.netid_multinet OWNER TO sysinfo;

--
-- Name: netid_multinet_history; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netid_multinet_history (
    sid integer NOT NULL,
    used integer,
    total integer,
    percent integer,
    seen timestamp without time zone
);


ALTER TABLE public.netid_multinet_history OWNER TO sysinfo;

--
-- Name: netid_range_sid_seq; Type: SEQUENCE; Schema: public; Owner: sysinfo
--

CREATE SEQUENCE netid_range_sid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.netid_range_sid_seq OWNER TO sysinfo;

--
-- Name: netid_range; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netid_range (
    multinet bigint NOT NULL,
    net_start bigint,
    net_end bigint,
    net_name text,
    range_start bigint,
    range_end bigint,
    range_name text,
    range_type text,
    first_seen timestamp without time zone,
    last_seen timestamp without time zone,
    sid integer DEFAULT nextval('netid_range_sid_seq'::regclass) NOT NULL
);


ALTER TABLE public.netid_range OWNER TO sysinfo;

--
-- Name: netid_range_history; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netid_range_history (
    sid integer NOT NULL,
    used integer,
    total integer,
    percent integer,
    seen timestamp without time zone
);


ALTER TABLE public.netid_range_history OWNER TO sysinfo;

--
-- Name: netscaler_members; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netscaler_members (
    host text NOT NULL,
    pool text NOT NULL,
    server text NOT NULL,
    ip inet,
    dns text NOT NULL,
    port text,
    lb_type text,
    state text,
    seen timestamp without time zone
);


ALTER TABLE public.netscaler_members OWNER TO sysinfo;

--
-- Name: netscaler_pools; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netscaler_pools (
    host text NOT NULL,
    service text NOT NULL,
    dns text,
    ip text,
    port text,
    lb_method text,
    lb_type text,
    persistance_type text,
    persistance_timeout text,
    state text,
    seen timestamp without time zone
);


ALTER TABLE public.netscaler_pools OWNER TO sysinfo;

--
-- Name: netscaler_relationships; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW netscaler_relationships AS
    SELECT iface.host, netscaler_pools.host AS netsc_host, netscaler_pools.service AS pool, netscaler_pools.state AS pool_state, netscaler_members.state AS member_state FROM netscaler_members, iface, save_heartbeat heartbeat, netscaler_pools WHERE ((((((netscaler_pools.service = netscaler_members.pool) AND (netscaler_pools.host = netscaler_members.host)) AND (netscaler_members.ip = iface.ip)) AND (iface.host = heartbeat.host)) AND (heartbeat.activity = 'active'::text)) AND (netscaler_pools.host IN (SELECT appliance_ha.host FROM appliance_ha WHERE ((appliance_ha.attribute = 'HaMode'::text) AND (appliance_ha.value = ANY (ARRAY['primary'::text, 'standalone'::text]))))));


ALTER TABLE public.netscaler_relationships OWNER TO sysinfo;

--
-- Name: netscaler_vlans; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE netscaler_vlans (
    host text NOT NULL,
    iface text NOT NULL,
    vlan integer NOT NULL,
    network inet NOT NULL,
    seen timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.netscaler_vlans OWNER TO sysinfo;

--
-- Name: network_groups_nid_seq; Type: SEQUENCE; Schema: public; Owner: sysinfo
--

CREATE SEQUENCE network_groups_nid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.network_groups_nid_seq OWNER TO sysinfo;

--
-- Name: network_groups; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE network_groups (
    name text NOT NULL,
    contact text,
    report boolean,
    nid integer DEFAULT nextval('network_groups_nid_seq'::regclass) NOT NULL,
    creation timestamp without time zone DEFAULT now()
);


ALTER TABLE public.network_groups OWNER TO sysinfo;

--
-- Name: network_mapping; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE network_mapping (
    network cidr NOT NULL,
    nid integer NOT NULL,
    creation timestamp without time zone DEFAULT now(),
    vlan text
);


ALTER TABLE public.network_mapping OWNER TO sysinfo;

--
-- Name: no_primary_key; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW no_primary_key AS
    SELECT pg_tables.schemaname, pg_tables.tablename, pg_tables.tableowner, pg_tables.tablespace, pg_tables.hasindexes, pg_tables.hasrules, pg_tables.hastriggers FROM pg_tables WHERE ((NOT (pg_tables.tablename IN (SELECT pg_indexes.tablename FROM pg_indexes WHERE ((pg_indexes.schemaname = 'public'::name) AND (pg_indexes.indexname ~~ '%_pkey'::text))))) AND (pg_tables.tableowner = 'sysinfo'::name));


ALTER TABLE public.no_primary_key OWNER TO sysinfo;

--
-- Name: os; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE os (
    host text NOT NULL,
    os text,
    os_version text,
    os_kernel text,
    os_arch text,
    seen timestamp without time zone
);


ALTER TABLE public.os OWNER TO sysinfo;

--
-- Name: pci; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE pci (
    host text NOT NULL,
    description text,
    seen timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.pci OWNER TO sysinfo;

--
-- Name: port_definitions; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE port_definitions (
    port integer,
    service text,
    class text
);


ALTER TABLE public.port_definitions OWNER TO sysinfo;

--
-- Name: process; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE process (
    host text NOT NULL,
    seen timestamp without time zone,
    process text NOT NULL,
    cmdline text,
    cwd text,
    exec text
);


ALTER TABLE public.process OWNER TO sysinfo;

--
-- Name: registered_user_tags; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE registered_user_tags (
    tag_name text NOT NULL
);


ALTER TABLE public.registered_user_tags OWNER TO sysinfo;

--
-- Name: relations; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE relations (
    type text NOT NULL,
    subject text NOT NULL,
    subject_col text NOT NULL,
    predicate text NOT NULL,
    predicate_col text NOT NULL,
    relation text NOT NULL,
    match text NOT NULL,
    seen timestamp without time zone DEFAULT now() NOT NULL,
    first_seen timestamp without time zone DEFAULT now()
);


ALTER TABLE public.relations OWNER TO sysinfo;

--
-- Name: relationships; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE relationships (
    host text NOT NULL,
    child text NOT NULL,
    type text,
    status text,
    comment text,
    seen timestamp without time zone
);


ALTER TABLE public.relationships OWNER TO sysinfo;

--
-- Name: remote_cons; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE remote_cons (
    host text,
    local_ip text,
    remote_ip text,
    port text,
    seen timestamp without time zone
);


ALTER TABLE public.remote_cons OWNER TO sysinfo;

--
-- Name: remote_hosts; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW remote_hosts AS
    SELECT iface.host, remote_cons.host AS remote_host, remote_cons.port FROM iface, remote_cons, save_heartbeat heartbeat WHERE (((iface.ip = (remote_cons.remote_ip)::inet) AND (iface.host = heartbeat.host)) AND (heartbeat.activity = 'active'::text));


ALTER TABLE public.remote_hosts OWNER TO sysinfo;

--
-- Name: root_level; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE root_level (
    host text NOT NULL,
    level text,
    seen timestamp without time zone
);


ALTER TABLE public.root_level OWNER TO sysinfo;

--
-- Name: scsi; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE scsi (
    host text,
    device text,
    vendor text,
    model text,
    rev text,
    type text,
    serial text,
    size text,
    seen timestamp without time zone
);


ALTER TABLE public.scsi OWNER TO sysinfo;

--
-- Name: service_deps; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE service_deps (
    sid integer NOT NULL,
    dep_sid integer NOT NULL,
    impact text
);


ALTER TABLE public.service_deps OWNER TO sysinfo;

--
-- Name: services_sid_seq; Type: SEQUENCE; Schema: public; Owner: sysinfo
--

CREATE SEQUENCE services_sid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.services_sid_seq OWNER TO sysinfo;

--
-- Name: services; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE services (
    name text NOT NULL,
    description text,
    availability text,
    sid integer DEFAULT nextval('services_sid_seq'::regclass)
);


ALTER TABLE public.services OWNER TO sysinfo;

--
-- Name: smartctl; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE smartctl (
    host text NOT NULL,
    drive text NOT NULL,
    device text NOT NULL,
    version text,
    serial text,
    capacity text,
    transport text,
    smart integer,
    seen timestamp without time zone
);


ALTER TABLE public.smartctl OWNER TO postgres;

--
-- Name: snag_server_definitions_seq; Type: SEQUENCE; Schema: public; Owner: sysinfo
--

CREATE SEQUENCE snag_server_definitions_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.snag_server_definitions_seq OWNER TO sysinfo;

--
-- Name: snag_server_definitions; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE snag_server_definitions (
    name text,
    server_host text NOT NULL,
    port text NOT NULL,
    key text,
    id integer DEFAULT nextval('snag_server_definitions_seq'::regclass),
    host text
);


ALTER TABLE public.snag_server_definitions OWNER TO sysinfo;

--
-- Name: snag_server_mappings; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE snag_server_mappings (
    server_id integer,
    host text NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.snag_server_mappings OWNER TO sysinfo;

--
-- Name: sysinfo_subnets_view; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW sysinfo_subnets_view AS
    SELECT DISTINCT bar.subnet FROM (SELECT ip4r_net_mask((foo.ip)::ip4, (foo.netmask)::ip4) AS subnet FROM (SELECT iface.ip, iface.netmask FROM (iface JOIN heartbeat USING (host)) WHERE ((((((((heartbeat.activity = 'active'::text) AND (iface.netmask IS NOT NULL)) AND (iface.netmask <> '0.0.0.0'::inet)) AND (iface.netmask <> '255.255.0.0'::inet)) AND (iface.netmask <> '255.0.0.0'::inet)) AND (iface.ip <> '0.0.0.0'::inet)) AND (iface.ip <> '127.0.0.1'::inet)) AND (iface.ip IS NOT NULL))) foo) bar ORDER BY bar.subnet;


ALTER TABLE public.sysinfo_subnets_view OWNER TO postgres;

--
-- Name: sysinfo_tags; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE sysinfo_tags (
    host text,
    tag text,
    seen timestamp without time zone
);


ALTER TABLE public.sysinfo_tags OWNER TO sysinfo;

--
-- Name: system; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW system AS
    SELECT device.host, device.vendor, device.model, device.model_type, device.serial, device.uuid, os.os, os.os_version, os.os_kernel, os.os_arch, bios.bios_vendor, bios.bios_version, bios.bios_date, cpumem.cpu, cpumem.cpu_speed, cpumem.cpu_cache, cpumem.cpu_count, cpumem.mem FROM (((device LEFT JOIN os ON ((device.host = os.host))) LEFT JOIN bios ON ((device.host = bios.host))) LEFT JOIN cpumem ON ((device.host = cpumem.host)));


ALTER TABLE public.system OWNER TO sysinfo;

--
-- Name: system_drac; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW system_drac AS
    SELECT device.host, drac_device.host AS drac FROM device, drac_device, save_heartbeat heartbeat WHERE (((heartbeat.host = device.host) AND (heartbeat.activity = 'active'::text)) AND (device.serial = drac_device.service_tag));


ALTER TABLE public.system_drac OWNER TO sysinfo;

--
-- Name: system_warranty; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE system_warranty (
    host text,
    serial text,
    description text,
    provider text,
    start_date date,
    end_date date
);


ALTER TABLE public.system_warranty OWNER TO sysinfo;

--
-- Name: table_comments; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE table_comments (
    host text NOT NULL,
    source_table text NOT NULL,
    key text NOT NULL,
    comment text
);


ALTER TABLE public.table_comments OWNER TO sysinfo;

--
-- Name: test; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE test (
    blah inet
);


ALTER TABLE public.test OWNER TO sysinfo;

--
-- Name: test_iface; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE test_iface (
    host text NOT NULL,
    iface text NOT NULL,
    type text,
    port text,
    mac macaddr,
    ip inet,
    netmask inet,
    speed text,
    duplex text,
    oper_state text,
    admin_state text,
    neg text,
    seen timestamp without time zone
);


ALTER TABLE public.test_iface OWNER TO sysinfo;

--
-- Name: tiface; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE tiface (
    host text NOT NULL,
    iface text NOT NULL,
    ip inet,
    mac macaddr,
    speed text,
    duplex text,
    neg text,
    seen timestamp without time zone,
    netmask inet
);


ALTER TABLE public.tiface OWNER TO sysinfo;

--
-- Name: tomcat_clusters; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE tomcat_clusters (
    host text NOT NULL,
    cluster_name text NOT NULL,
    status text,
    app text NOT NULL
);


ALTER TABLE public.tomcat_clusters OWNER TO sysinfo;

--
-- Name: tooltips; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE tooltips (
    id text,
    title text,
    body text
);


ALTER TABLE public.tooltips OWNER TO sysinfo;

--
-- Name: update_payload_payload_id_seq; Type: SEQUENCE; Schema: public; Owner: sysinfo
--

CREATE SEQUENCE update_payload_payload_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.update_payload_payload_id_seq OWNER TO sysinfo;

--
-- Name: update_payload; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE update_payload (
    payload_id integer DEFAULT nextval('update_payload_payload_id_seq'::regclass) NOT NULL,
    name text NOT NULL,
    signature text NOT NULL,
    filename text NOT NULL
);


ALTER TABLE public.update_payload OWNER TO sysinfo;

--
-- Name: update_queue; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE update_queue (
    host text NOT NULL,
    time_created timestamp without time zone DEFAULT now() NOT NULL,
    time_completed timestamp without time zone,
    is_complete boolean DEFAULT true NOT NULL,
    payload_id integer NOT NULL
);


ALTER TABLE public.update_queue OWNER TO sysinfo;

--
-- Name: vmware_uuids; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE vmware_uuids (
    host text NOT NULL,
    display_name text,
    uuid text NOT NULL,
    seen timestamp without time zone
);


ALTER TABLE public.vmware_uuids OWNER TO sysinfo;

--
-- Name: vmware_guests; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW vmware_guests AS
    SELECT vmware_uuids.host, vmware_uuids.display_name, vmware_uuids.uuid, device.host AS guest, os.os, heartbeat.activity, heartbeat.seen FROM (((vmware_uuids LEFT JOIN device ON ((device.serial = vmware_uuids.uuid))) LEFT JOIN save_heartbeat heartbeat ON ((device.host = heartbeat.host))) LEFT JOIN os ON ((os.host = device.host)));


ALTER TABLE public.vmware_guests OWNER TO sysinfo;

--
-- Name: was_apps; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE was_apps (
    host text NOT NULL,
    app text NOT NULL,
    seen timestamp without time zone
);


ALTER TABLE public.was_apps OWNER TO sysinfo;

--
-- Name: xen_dom0; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE xen_dom0 (
    host text NOT NULL,
    uuid text NOT NULL,
    domid integer,
    name text,
    seen timestamp without time zone
);


ALTER TABLE public.xen_dom0 OWNER TO sysinfo;

--
-- Name: xen_guests; Type: VIEW; Schema: public; Owner: sysinfo
--

CREATE VIEW xen_guests AS
    SELECT xen_dom0.host, xen_dom0.name AS display_name, xen_dom0.uuid, device.host AS guest, os.os, heartbeat.activity, heartbeat.seen FROM (((xen_dom0 LEFT JOIN device ON ((device.uuid = xen_dom0.uuid))) LEFT JOIN save_heartbeat heartbeat ON ((device.host = heartbeat.host))) LEFT JOIN os ON ((os.host = device.host)));


ALTER TABLE public.xen_guests OWNER TO sysinfo;

--
-- Name: xen_inventory; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE xen_inventory (
    host text NOT NULL,
    installed text,
    xen_version text,
    xen_build text,
    product_version text,
    uuid text,
    seen timestamp without time zone
);


ALTER TABLE public.xen_inventory OWNER TO sysinfo;

--
-- Name: xen_pif; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE xen_pif (
    host text NOT NULL,
    uuid text NOT NULL,
    network_name_label text,
    vlan text,
    device text,
    attached text,
    network_uuid text,
    seen timestamp without time zone
);


ALTER TABLE public.xen_pif OWNER TO sysinfo;

--
-- Name: xen_pool; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE xen_pool (
    host text NOT NULL,
    name text,
    description text,
    member_uuid text,
    master_uuid text,
    master_name text,
    seen timestamp without time zone
);


ALTER TABLE public.xen_pool OWNER TO sysinfo;

--
-- Name: xen_sr; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE xen_sr (
    host text NOT NULL,
    uuid text NOT NULL,
    name text,
    type text,
    description text,
    owner text,
    ip inet,
    endpoint text,
    seen timestamp without time zone
);


ALTER TABLE public.xen_sr OWNER TO sysinfo;

--
-- Name: xen_uuids; Type: TABLE; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE TABLE xen_uuids (
    host text,
    uuid text,
    domid integer,
    seen timestamp without time zone
);


ALTER TABLE public.xen_uuids OWNER TO sysinfo;

--
-- Name: alert_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY alert_settings
    ADD CONSTRAINT alert_settings_pkey PRIMARY KEY (source, category, alert);


--
-- Name: appliance_config_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY appliance_config
    ADD CONSTRAINT appliance_config_pkey PRIMARY KEY (host, attribute);


--
-- Name: appliance_features_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY appliance_features
    ADD CONSTRAINT appliance_features_pkey PRIMARY KEY (host, feature);


--
-- Name: appliance_ha_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY appliance_ha
    ADD CONSTRAINT appliance_ha_pkey PRIMARY KEY (host, attribute);


--
-- Name: appliance_modes_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY appliance_modes
    ADD CONSTRAINT appliance_modes_pkey PRIMARY KEY (host, mode);


--
-- Name: appliance_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY appliance
    ADD CONSTRAINT appliance_pkey PRIMARY KEY (host);


--
-- Name: appliance_status_idx; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY appliance_status
    ADD CONSTRAINT appliance_status_idx PRIMARY KEY (host, status);


--
-- Name: asl_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY asl
    ADD CONSTRAINT asl_pkey PRIMARY KEY (host);


--
-- Name: asl_server_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY snag_server_definitions
    ADD CONSTRAINT asl_server_definitions_pkey PRIMARY KEY (server_host, port);


--
-- Name: asl_server_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY snag_server_mappings
    ADD CONSTRAINT asl_server_mappings_pkey PRIMARY KEY (host, name);


--
-- Name: bios_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY bios
    ADD CONSTRAINT bios_pkey PRIMARY KEY (host);


--
-- Name: bridge_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY bridge
    ADD CONSTRAINT bridge_pkey PRIMARY KEY (host, bridge, interface);


--
-- Name: brmac_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY brmac
    ADD CONSTRAINT brmac_pkey PRIMARY KEY (host, bridge, mac);


--
-- Name: cca_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY cca
    ADD CONSTRAINT cca_pkey PRIMARY KEY (host, farm_dns);


--
-- Name: conf_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY conf
    ADD CONSTRAINT conf_pkey PRIMARY KEY (host, source);


--
-- Name: cpumem_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY cpumem
    ADD CONSTRAINT cpumem_pkey PRIMARY KEY (host);


--
-- Name: description_history_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY description_history
    ADD CONSTRAINT description_history_pkey PRIMARY KEY (host, col, val, uid, seen);


--
-- Name: description_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY description
    ADD CONSTRAINT description_pkey PRIMARY KEY (host);


--
-- Name: device_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY device
    ADD CONSTRAINT device_pkey PRIMARY KEY (host);


--
-- Name: disk_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY disk
    ADD CONSTRAINT disk_pkey PRIMARY KEY (host, device);


--
-- Name: dns_aliases_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY dns_aliases
    ADD CONSTRAINT dns_aliases_pkey PRIMARY KEY (host, ip, alias);


--
-- Name: domain_map_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY domain_map
    ADD CONSTRAINT domain_map_pkey PRIMARY KEY (subnet);


--
-- Name: drac_console_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY drac_console
    ADD CONSTRAINT drac_console_pkey PRIMARY KEY (host);


--
-- Name: drac_device_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY drac_device
    ADD CONSTRAINT drac_device_pkey PRIMARY KEY (host);


--
-- Name: drac_os_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY drac_os
    ADD CONSTRAINT drac_os_pkey PRIMARY KEY (host);


--
-- Name: edna_server_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY edna_server
    ADD CONSTRAINT edna_server_pkey PRIMARY KEY (host, version);


--
-- Name: entity_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY entity_mappings
    ADD CONSTRAINT entity_mappings_pkey PRIMARY KEY (entity_type, component);


--
-- Name: entity_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY entity
    ADD CONSTRAINT entity_pkey PRIMARY KEY (host);

ALTER TABLE entity CLUSTER ON entity_pkey;


--
-- Name: hardware_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY hardware_inventory
    ADD CONSTRAINT hardware_inventory_pkey PRIMARY KEY (serial);


--
-- Name: heartbeat_asl_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY heartbeat_asl
    ADD CONSTRAINT heartbeat_asl_pkey PRIMARY KEY (host);


--
-- Name: heartbeat_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY save_heartbeat
    ADD CONSTRAINT heartbeat_pkey PRIMARY KEY (host);

ALTER TABLE save_heartbeat CLUSTER ON heartbeat_pkey;


--
-- Name: heartbeat_syslog_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY heartbeat_syslog
    ADD CONSTRAINT heartbeat_syslog_pkey PRIMARY KEY (host, fqdn, loghost);


--
-- Name: hist_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY hist
    ADD CONSTRAINT hist_pkey PRIMARY KEY (index);


--
-- Name: host_passwd_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY host_passwd
    ADD CONSTRAINT host_passwd_pkey PRIMARY KEY (host, name);


--
-- Name: listening_ports_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY listening_ports
    ADD CONSTRAINT listening_ports_pkey PRIMARY KEY (host, addr, port);


--
-- Name: meta_membership_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY meta_membership
    ADD CONSTRAINT meta_membership_pkey PRIMARY KEY (meta_name, meta_table);


--
-- Name: meta_web_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY meta_web_alias
    ADD CONSTRAINT meta_web_alias_pkey PRIMARY KEY (meta_name, host, address, source);


--
-- Name: meta_web_redirect_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY meta_web_redirect
    ADD CONSTRAINT meta_web_redirect_pkey PRIMARY KEY (meta_name, host, match, destination);


--
-- Name: meta_web_vhost_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY meta_web_vhost
    ADD CONSTRAINT meta_web_vhost_pkey PRIMARY KEY (meta_name, host, port, doc_root);


--
-- Name: monitor_defs_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY monitor_defs
    ADD CONSTRAINT monitor_defs_pkey PRIMARY KEY (host);


--
-- Name: netapp_aggregates_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netapp_aggregates
    ADD CONSTRAINT netapp_aggregates_pkey PRIMARY KEY (host, name, aggr_id);


--
-- Name: netapp_device_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netapp_device
    ADD CONSTRAINT netapp_device_pkey PRIMARY KEY (host);


--
-- Name: netapp_df_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netapp_df
    ADD CONSTRAINT netapp_df_pkey PRIMARY KEY (host, df_id);


--
-- Name: netapp_fcp_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netapp_fcp
    ADD CONSTRAINT netapp_fcp_pkey PRIMARY KEY (host, name);


--
-- Name: netapp_features_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netapp_features
    ADD CONSTRAINT netapp_features_pkey PRIMARY KEY (host, feature);


--
-- Name: netapp_iface_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netapp_iface
    ADD CONSTRAINT netapp_iface_pkey PRIMARY KEY (host, port);


--
-- Name: netapp_os_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netapp_os
    ADD CONSTRAINT netapp_os_pkey PRIMARY KEY (host);


--
-- Name: netapp_qtrees_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netapp_qtrees
    ADD CONSTRAINT netapp_qtrees_pkey PRIMARY KEY (host, idx);


--
-- Name: netapp_volumes_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netapp_volumes
    ADD CONSTRAINT netapp_volumes_pkey PRIMARY KEY (host, name, volume_id);


--
-- Name: netscaler_members_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netscaler_members
    ADD CONSTRAINT netscaler_members_pkey PRIMARY KEY (host, pool, server);


--
-- Name: netscaler_pools_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netscaler_pools
    ADD CONSTRAINT netscaler_pools_pkey PRIMARY KEY (host, service);


--
-- Name: netscaler_vlans_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY netscaler_vlans
    ADD CONSTRAINT netscaler_vlans_pkey PRIMARY KEY (host, iface, vlan, network);


--
-- Name: network_groups_name_key; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY network_groups
    ADD CONSTRAINT network_groups_name_key UNIQUE (name);


--
-- Name: network_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY network_groups
    ADD CONSTRAINT network_groups_pkey PRIMARY KEY (nid);


--
-- Name: network_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY network_mapping
    ADD CONSTRAINT network_mapping_pkey PRIMARY KEY (network, nid);


--
-- Name: os_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY os
    ADD CONSTRAINT os_pkey PRIMARY KEY (host);


--
-- Name: registered_user_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY registered_user_tags
    ADD CONSTRAINT registered_user_tags_pkey PRIMARY KEY (tag_name);


--
-- Name: relations_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY relations
    ADD CONSTRAINT relations_pkey PRIMARY KEY (type, subject, predicate, relation, match);


--
-- Name: relationships_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY relationships
    ADD CONSTRAINT relationships_pkey PRIMARY KEY (host, child);


--
-- Name: root_level_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY root_level
    ADD CONSTRAINT root_level_pkey PRIMARY KEY (host);


--
-- Name: server_heartbeats_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY server_heartbeats
    ADD CONSTRAINT server_heartbeats_pkey PRIMARY KEY (host, server, source);


--
-- Name: service_deps_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY service_deps
    ADD CONSTRAINT service_deps_pkey PRIMARY KEY (sid, dep_sid);


--
-- Name: services_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY services
    ADD CONSTRAINT services_pkey PRIMARY KEY (name);


--
-- Name: services_sid_key; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY services
    ADD CONSTRAINT services_sid_key UNIQUE (sid);


--
-- Name: table_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY table_comments
    ADD CONSTRAINT table_comments_pkey PRIMARY KEY (host, source_table, key);


--
-- Name: tags_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (host, tag, category, multi);


--
-- Name: test_iface_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY test_iface
    ADD CONSTRAINT test_iface_pkey PRIMARY KEY (host, iface);


--
-- Name: tiface_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY tiface
    ADD CONSTRAINT tiface_pkey PRIMARY KEY (host, iface);


--
-- Name: tomcat_clusters_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY tomcat_clusters
    ADD CONSTRAINT tomcat_clusters_pkey PRIMARY KEY (host, cluster_name, app);


--
-- Name: update_payload_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY update_payload
    ADD CONSTRAINT update_payload_pkey PRIMARY KEY (payload_id);


--
-- Name: update_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY update_queue
    ADD CONSTRAINT update_queue_pkey PRIMARY KEY (host, time_created, is_complete, payload_id);


--
-- Name: vmware_uuids_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY vmware_uuids
    ADD CONSTRAINT vmware_uuids_pkey PRIMARY KEY (host, uuid);


--
-- Name: was_apps_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY was_apps
    ADD CONSTRAINT was_apps_pkey PRIMARY KEY (host, app);


--
-- Name: xen_dom0_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY xen_dom0
    ADD CONSTRAINT xen_dom0_pkey PRIMARY KEY (host, uuid);


--
-- Name: xen_pif_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY xen_pif
    ADD CONSTRAINT xen_pif_pkey PRIMARY KEY (host, uuid);


--
-- Name: xen_sr_pkey; Type: CONSTRAINT; Schema: public; Owner: sysinfo; Tablespace: 
--

ALTER TABLE ONLY xen_sr
    ADD CONSTRAINT xen_sr_pkey PRIMARY KEY (host, uuid);


--
-- Name: alerts_alert_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX alerts_alert_idx ON alerts USING btree (alert);


--
-- Name: alerts_last_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX alerts_last_seen_idx ON alerts USING btree (last_seen);


--
-- Name: alerts_pkey; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE UNIQUE INDEX alerts_pkey ON alerts USING btree (aid);


--
-- Name: arp_host_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX arp_host_idx ON arp USING btree (host);


--
-- Name: arp_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX arp_seen_idx ON arp USING btree (seen);


--
-- Name: description_location_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX description_location_idx ON description USING btree (location);


--
-- Name: device_model_vendor_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX device_model_vendor_idx ON device USING btree (model, vendor);


--
-- Name: device_vendor_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX device_vendor_idx ON device USING btree (vendor);


--
-- Name: disk_host_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX disk_host_idx ON disk USING btree (host);


--
-- Name: dns_aliases_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX dns_aliases_idx ON dns_aliases USING btree (alias);


--
-- Name: drac_console_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX drac_console_seen_idx ON drac_console USING btree (seen);


--
-- Name: drac_console_url_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX drac_console_url_idx ON drac_console USING btree (host, url);


--
-- Name: drac_device_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX drac_device_seen_idx ON drac_device USING btree (seen);


--
-- Name: drac_os_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX drac_os_seen_idx ON drac_os USING btree (seen);


--
-- Name: events_aid_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX events_aid_seen_idx ON events USING btree (aid, seen);


--
-- Name: events_pkey; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE UNIQUE INDEX events_pkey ON events USING btree (eid);


--
-- Name: fiber_host_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX fiber_host_idx ON fiber USING btree (host);


--
-- Name: first_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX first_seen_idx ON netid_multinet USING btree (first_seen);


--
-- Name: heartbeat_asl_source_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX heartbeat_asl_source_seen_idx ON heartbeat_asl USING btree (source, seen);


--
-- Name: hist_full_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX hist_full_idx ON hist USING btree (host, tab, source, seen);


--
-- Name: hist_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX hist_seen_idx ON hist USING btree (seen);


--
-- Name: hist_tab_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX hist_tab_idx ON hist USING btree (tab);


--
-- Name: idx_alert_host; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_alert_host ON alerts USING btree (host);


--
-- Name: idx_alert_setting_severity; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_alert_setting_severity ON alert_settings USING btree (severity);


--
-- Name: idx_alert_settings_alert; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_alert_settings_alert ON alert_settings USING btree (alert);


--
-- Name: idx_alert_settings_category; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_alert_settings_category ON alert_settings USING btree (category);


--
-- Name: idx_alert_settings_source; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_alert_settings_source ON alert_settings USING btree (source);


--
-- Name: idx_conf_host; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_conf_host ON conf USING btree (host);


--
-- Name: idx_conf_source; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_conf_source ON conf USING btree (source);


--
-- Name: idx_cpumem_host; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_cpumem_host ON cpumem USING btree (host);


--
-- Name: idx_description_status; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_description_status ON description USING btree (status);


--
-- Name: idx_device_uuid; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_device_uuid ON device USING btree (uuid);


--
-- Name: idx_entity_type; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_entity_type ON entity USING btree (type);


--
-- Name: idx_heartbeat_activity_seen; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_heartbeat_activity_seen ON save_heartbeat USING btree (activity, seen);


--
-- Name: idx_listening_ports_port; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_listening_ports_port ON listening_ports USING btree (port);


--
-- Name: idx_relationships_child; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_relationships_child ON relationships USING btree (child);


--
-- Name: idx_relationships_host; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_relationships_host ON relationships USING btree (host);


--
-- Name: idx_tags_tag; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_tags_tag ON tags USING btree (tag);


--
-- Name: idx_xen_dom0_host; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX idx_xen_dom0_host ON xen_dom0 USING btree (host);


--
-- Name: iface_ip_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX iface_ip_idx ON iface USING btree (ip);


--
-- Name: iface_mac_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX iface_mac_idx ON iface USING btree (mac);


--
-- Name: iface_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX iface_seen_idx ON iface USING btree (seen);


--
-- Name: last_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX last_seen_idx ON netid_multinet USING btree (last_seen);


--
-- Name: multinet_hist_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX multinet_hist_seen_idx ON netid_multinet_history USING btree (seen);


--
-- Name: multinet_history_sid_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX multinet_history_sid_idx ON netid_multinet_history USING btree (sid);


--
-- Name: netapp_device_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX netapp_device_seen_idx ON netapp_device USING btree (seen);


--
-- Name: netapp_iface_ip_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX netapp_iface_ip_idx ON netapp_iface USING btree (ip);


--
-- Name: netapp_iface_mac_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX netapp_iface_mac_idx ON netapp_iface USING btree (mac);


--
-- Name: netapp_os_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX netapp_os_seen_idx ON netapp_os USING btree (seen);


--
-- Name: netid_multinet_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE UNIQUE INDEX netid_multinet_idx ON netid_multinet USING btree (multinet);


--
-- Name: netid_multinet_sid_ids; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX netid_multinet_sid_ids ON netid_multinet USING btree (sid);


--
-- Name: netid_range_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE UNIQUE INDEX netid_range_idx ON netid_range USING btree (multinet, net_start, net_end, range_start, range_end);


--
-- Name: netscaler_members_dns_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX netscaler_members_dns_idx ON netscaler_members USING btree (dns);


--
-- Name: netscaler_pools_dns_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX netscaler_pools_dns_idx ON netscaler_pools USING btree (dns);


--
-- Name: netscaler_pools_ip_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX netscaler_pools_ip_idx ON netscaler_pools USING btree (ip);


--
-- Name: os_os_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX os_os_idx ON os USING btree (os);


--
-- Name: os_os_version_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX os_os_version_idx ON os USING btree (os_version);


--
-- Name: pci_host_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX pci_host_idx ON pci USING btree (host);


--
-- Name: predicate_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX predicate_idx ON relations USING btree (predicate);


--
-- Name: process_cmdline_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX process_cmdline_idx ON process USING btree (cmdline);


--
-- Name: process_host_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX process_host_idx ON process USING btree (host);


--
-- Name: process_process_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX process_process_idx ON process USING btree (process);


--
-- Name: process_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX process_seen_idx ON process USING btree (seen);


--
-- Name: range_first_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX range_first_seen_idx ON netid_range USING btree (first_seen);


--
-- Name: range_hist_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX range_hist_seen_idx ON netid_range_history USING btree (seen);


--
-- Name: range_history_sid_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX range_history_sid_idx ON netid_range_history USING btree (sid);


--
-- Name: range_last_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX range_last_seen_idx ON netid_range USING btree (last_seen);


--
-- Name: scsi_host_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX scsi_host_idx ON scsi USING btree (host);


--
-- Name: subject_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX subject_idx ON relations USING btree (subject);


--
-- Name: tags_category_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX tags_category_idx ON tags USING btree (category);


--
-- Name: tags_tag_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX tags_tag_seen_idx ON tags USING btree (tag, seen);


--
-- Name: test_iface_ip_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX test_iface_ip_idx ON test_iface USING btree (ip);


--
-- Name: test_iface_mac_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX test_iface_mac_idx ON test_iface USING btree (mac);


--
-- Name: test_iface_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX test_iface_seen_idx ON test_iface USING btree (seen);


--
-- Name: tiface_ip_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX tiface_ip_idx ON tiface USING btree (ip);


--
-- Name: tiface_mac_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX tiface_mac_idx ON tiface USING btree (mac);


--
-- Name: tiface_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX tiface_seen_idx ON tiface USING btree (seen);


--
-- Name: vlan_network_uidx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE UNIQUE INDEX vlan_network_uidx ON network_mapping USING btree (vlan, network);


--
-- Name: vmware_uuids_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX vmware_uuids_idx ON vmware_uuids USING btree (uuid);


--
-- Name: xen_dom0_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX xen_dom0_idx ON xen_dom0 USING btree (uuid);


--
-- Name: xen_pif_seen_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX xen_pif_seen_idx ON xen_pif USING btree (seen);


--
-- Name: xen_pif_vlan; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX xen_pif_vlan ON xen_dom0 USING btree (uuid);


--
-- Name: xen_pif_vlan_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX xen_pif_vlan_idx ON xen_pif USING btree (vlan);


--
-- Name: xen_sr_name_idx; Type: INDEX; Schema: public; Owner: sysinfo; Tablespace: 
--

CREATE INDEX xen_sr_name_idx ON xen_sr USING btree (name);


--
-- Name: get_alert_aid_seq; Type: RULE; Schema: public; Owner: sysinfo
--

CREATE RULE get_alert_aid_seq AS ON INSERT TO alerts DO SELECT currval(('alerts_aid_seq'::text)::regclass) AS aid;


--
-- Name: iface_notify; Type: TRIGGER; Schema: public; Owner: sysinfo
--

CREATE TRIGGER iface_notify AFTER INSERT OR UPDATE ON iface FOR EACH ROW EXECUTE PROCEDURE iface_notify();


--
-- Name: t_alias_after; Type: TRIGGER; Schema: public; Owner: sysinfo
--

CREATE TRIGGER t_alias_after AFTER INSERT OR UPDATE ON meta_web_alias FOR EACH ROW EXECUTE PROCEDURE meta_upsert();


--
-- Name: t_env_after; Type: TRIGGER; Schema: public; Owner: sysinfo
--

CREATE TRIGGER t_env_after AFTER INSERT OR UPDATE ON description FOR EACH ROW EXECUTE PROCEDURE tag_env_upsert();


--
-- Name: t_redirect_after; Type: TRIGGER; Schema: public; Owner: sysinfo
--

CREATE TRIGGER t_redirect_after AFTER INSERT OR UPDATE ON meta_web_redirect FOR EACH ROW EXECUTE PROCEDURE meta_upsert();


--
-- Name: t_status_after; Type: TRIGGER; Schema: public; Owner: sysinfo
--

CREATE TRIGGER t_status_after AFTER INSERT OR UPDATE ON description FOR EACH ROW EXECUTE PROCEDURE tag_status_upsert();


--
-- Name: t_tiface_before; Type: TRIGGER; Schema: public; Owner: sysinfo
--

CREATE TRIGGER t_tiface_before BEFORE INSERT OR UPDATE ON tiface FOR EACH ROW EXECUTE PROCEDURE tiface_check();


--
-- Name: t_vhost_after; Type: TRIGGER; Schema: public; Owner: sysinfo
--

CREATE TRIGGER t_vhost_after AFTER INSERT OR UPDATE ON meta_web_vhost FOR EACH ROW EXECUTE PROCEDURE meta_upsert();


--
-- Name: tiface_test; Type: TRIGGER; Schema: public; Owner: sysinfo
--

CREATE TRIGGER tiface_test BEFORE UPDATE ON tiface FOR EACH ROW EXECUTE PROCEDURE ti_notify();


--
-- Name: event_fk_aid; Type: FK CONSTRAINT; Schema: public; Owner: sysinfo
--

ALTER TABLE ONLY events
    ADD CONSTRAINT event_fk_aid FOREIGN KEY (aid) REFERENCES alerts(aid) ON DELETE CASCADE;


--
-- Name: network_mapping_nid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sysinfo
--

ALTER TABLE ONLY network_mapping
    ADD CONSTRAINT network_mapping_nid_fkey FOREIGN KEY (nid) REFERENCES network_groups(nid);


--
-- Name: update_queue_host_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sysinfo
--

ALTER TABLE ONLY update_queue
    ADD CONSTRAINT update_queue_host_fkey FOREIGN KEY (host) REFERENCES entity(host);


--
-- Name: update_queue_payload_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sysinfo
--

ALTER TABLE ONLY update_queue
    ADD CONSTRAINT update_queue_payload_id_fkey FOREIGN KEY (payload_id) REFERENCES update_payload(payload_id);


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- Name: alert_settings; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE alert_settings FROM PUBLIC;
REVOKE ALL ON TABLE alert_settings FROM sysinfo;
GRANT ALL ON TABLE alert_settings TO sysinfo;
GRANT ALL ON TABLE alert_settings TO sysinfo_asls_alerts;


--
-- Name: alerts_aid_seq; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON SEQUENCE alerts_aid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE alerts_aid_seq FROM sysinfo;
GRANT ALL ON SEQUENCE alerts_aid_seq TO sysinfo;
GRANT ALL ON SEQUENCE alerts_aid_seq TO sysinfo_asls_alerts;


--
-- Name: alerts; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE alerts FROM PUBLIC;
REVOKE ALL ON TABLE alerts FROM sysinfo;
GRANT ALL ON TABLE alerts TO sysinfo;
GRANT ALL ON TABLE alerts TO sysinfo_asls_alerts;


--
-- Name: appliance; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE appliance FROM PUBLIC;
REVOKE ALL ON TABLE appliance FROM sysinfo;
GRANT ALL ON TABLE appliance TO sysinfo;
GRANT SELECT ON TABLE appliance TO sysinforo;


--
-- Name: appliance_config; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE appliance_config FROM PUBLIC;
REVOKE ALL ON TABLE appliance_config FROM sysinfo;
GRANT ALL ON TABLE appliance_config TO sysinfo;
GRANT SELECT ON TABLE appliance_config TO sysinforo;


--
-- Name: appliance_features; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE appliance_features FROM PUBLIC;
REVOKE ALL ON TABLE appliance_features FROM sysinfo;
GRANT ALL ON TABLE appliance_features TO sysinfo;
GRANT SELECT ON TABLE appliance_features TO sysinforo;


--
-- Name: appliance_ha; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE appliance_ha FROM PUBLIC;
REVOKE ALL ON TABLE appliance_ha FROM sysinfo;
GRANT ALL ON TABLE appliance_ha TO sysinfo;
GRANT SELECT ON TABLE appliance_ha TO sysinforo;


--
-- Name: appliance_modes; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE appliance_modes FROM PUBLIC;
REVOKE ALL ON TABLE appliance_modes FROM sysinfo;
GRANT ALL ON TABLE appliance_modes TO sysinfo;
GRANT SELECT ON TABLE appliance_modes TO sysinforo;


--
-- Name: arp; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE arp FROM PUBLIC;
REVOKE ALL ON TABLE arp FROM sysinfo;
GRANT ALL ON TABLE arp TO sysinfo;
GRANT SELECT ON TABLE arp TO sysinforo;


--
-- Name: arptest; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE arptest FROM PUBLIC;
REVOKE ALL ON TABLE arptest FROM sysinfo;
GRANT ALL ON TABLE arptest TO sysinfo;
GRANT SELECT ON TABLE arptest TO sysinforo;


--
-- Name: asl; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE asl FROM PUBLIC;
REVOKE ALL ON TABLE asl FROM sysinfo;
GRANT ALL ON TABLE asl TO sysinfo;
GRANT SELECT ON TABLE asl TO sysinforo;
GRANT SELECT ON TABLE asl TO sysinfo_aslp_hb;
GRANT SELECT ON TABLE asl TO sysinfo_aslp_aslhb;


--
-- Name: bigip; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE bigip FROM PUBLIC;
REVOKE ALL ON TABLE bigip FROM sysinfo;
GRANT ALL ON TABLE bigip TO sysinfo;
GRANT SELECT ON TABLE bigip TO sysinforo;


--
-- Name: bigip_pools; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE bigip_pools FROM PUBLIC;
REVOKE ALL ON TABLE bigip_pools FROM sysinfo;
GRANT ALL ON TABLE bigip_pools TO sysinfo;
GRANT SELECT ON TABLE bigip_pools TO sysinforo;


--
-- Name: bios; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE bios FROM PUBLIC;
REVOKE ALL ON TABLE bios FROM sysinfo;
GRANT ALL ON TABLE bios TO sysinfo;
GRANT SELECT ON TABLE bios TO sysinforo;


--
-- Name: conf; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE conf FROM PUBLIC;
REVOKE ALL ON TABLE conf FROM sysinfo;
GRANT ALL ON TABLE conf TO sysinfo;
GRANT SELECT ON TABLE conf TO sysinforo;


--
-- Name: cpumem; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE cpumem FROM PUBLIC;
REVOKE ALL ON TABLE cpumem FROM sysinfo;
GRANT ALL ON TABLE cpumem TO sysinfo;
GRANT SELECT ON TABLE cpumem TO sysinforo;


--
-- Name: description; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE description FROM PUBLIC;
REVOKE ALL ON TABLE description FROM sysinfo;
GRANT ALL ON TABLE description TO sysinfo;
GRANT SELECT ON TABLE description TO sysinforo;
GRANT SELECT ON TABLE description TO sysinfo_aslp_hb;
GRANT SELECT ON TABLE description TO sysinfo_aslp_aslhb;


--
-- Name: description_backup; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE description_backup FROM PUBLIC;
REVOKE ALL ON TABLE description_backup FROM sysinfo;
GRANT ALL ON TABLE description_backup TO sysinfo;
GRANT SELECT ON TABLE description_backup TO sysinforo;


--
-- Name: device; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE device FROM PUBLIC;
REVOKE ALL ON TABLE device FROM sysinfo;
GRANT ALL ON TABLE device TO sysinfo;
GRANT SELECT ON TABLE device TO sysinforo;


--
-- Name: disk; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE disk FROM PUBLIC;
REVOKE ALL ON TABLE disk FROM sysinfo;
GRANT ALL ON TABLE disk TO sysinfo;
GRANT SELECT ON TABLE disk TO sysinforo;


--
-- Name: domain_map; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE domain_map FROM PUBLIC;
REVOKE ALL ON TABLE domain_map FROM sysinfo;
GRANT ALL ON TABLE domain_map TO sysinfo;
GRANT SELECT ON TABLE domain_map TO sysinforo;
GRANT SELECT ON TABLE domain_map TO sysinfo_asls_master;


--
-- Name: save_heartbeat; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE save_heartbeat FROM PUBLIC;
REVOKE ALL ON TABLE save_heartbeat FROM sysinfo;
GRANT ALL ON TABLE save_heartbeat TO sysinfo;
GRANT SELECT ON TABLE save_heartbeat TO sysinforo;
GRANT ALL ON TABLE save_heartbeat TO sysinfo_asls_alerts;
GRANT SELECT ON TABLE save_heartbeat TO sysinfo_asls_sysinfo;
GRANT SELECT ON TABLE save_heartbeat TO sysinfo_aslp_hb;


--
-- Name: events_eid_seq; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON SEQUENCE events_eid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE events_eid_seq FROM sysinfo;
GRANT ALL ON SEQUENCE events_eid_seq TO sysinfo;
GRANT ALL ON SEQUENCE events_eid_seq TO sysinfo_asls_alerts;


--
-- Name: events; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE events FROM PUBLIC;
REVOKE ALL ON TABLE events FROM sysinfo;
GRANT ALL ON TABLE events TO sysinfo;
GRANT ALL ON TABLE events TO sysinfo_asls_alerts;


--
-- Name: fiber; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE fiber FROM PUBLIC;
REVOKE ALL ON TABLE fiber FROM sysinfo;
GRANT ALL ON TABLE fiber TO sysinfo;
GRANT SELECT ON TABLE fiber TO sysinforo;


--
-- Name: hbtest; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE hbtest FROM PUBLIC;
REVOKE ALL ON TABLE hbtest FROM sysinfo;
GRANT ALL ON TABLE hbtest TO sysinfo;
GRANT SELECT ON TABLE hbtest TO sysinforo;


--
-- Name: server_heartbeats; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE server_heartbeats FROM PUBLIC;
REVOKE ALL ON TABLE server_heartbeats FROM sysinfo;
GRANT ALL ON TABLE server_heartbeats TO sysinfo;
GRANT ALL ON TABLE server_heartbeats TO sysinfo_asls_alerts;
GRANT SELECT ON TABLE server_heartbeats TO sysinfo_aslp_aslhb;
GRANT ALL ON TABLE server_heartbeats TO sysinfo_asls_master;


--
-- Name: heartbeat; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE heartbeat FROM PUBLIC;
REVOKE ALL ON TABLE heartbeat FROM sysinfo;
GRANT ALL ON TABLE heartbeat TO sysinfo;
GRANT SELECT ON TABLE heartbeat TO sysinfo_aslp_hb;


--
-- Name: heartbeat_asl; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE heartbeat_asl FROM PUBLIC;
REVOKE ALL ON TABLE heartbeat_asl FROM sysinfo;
GRANT ALL ON TABLE heartbeat_asl TO sysinfo;
GRANT SELECT ON TABLE heartbeat_asl TO sysinforo;


--
-- Name: heartbeat_syslog; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE heartbeat_syslog FROM PUBLIC;
REVOKE ALL ON TABLE heartbeat_syslog FROM sysinfo;
GRANT ALL ON TABLE heartbeat_syslog TO sysinfo;
GRANT SELECT ON TABLE heartbeat_syslog TO sysinforo;
GRANT ALL ON TABLE heartbeat_syslog TO sysinfo_asls_alerts;


--
-- Name: hist; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE hist FROM PUBLIC;
REVOKE ALL ON TABLE hist FROM sysinfo;
GRANT ALL ON TABLE hist TO sysinfo;
GRANT SELECT ON TABLE hist TO sysinforo;


--
-- Name: iface; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE iface FROM PUBLIC;
REVOKE ALL ON TABLE iface FROM sysinfo;
GRANT ALL ON TABLE iface TO sysinfo;
GRANT SELECT ON TABLE iface TO sysinforo;


--
-- Name: md; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE md FROM PUBLIC;
REVOKE ALL ON TABLE md FROM sysinfo;
GRANT ALL ON TABLE md TO sysinfo;
GRANT SELECT ON TABLE md TO sysinforo;


--
-- Name: netscaler_members; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE netscaler_members FROM PUBLIC;
REVOKE ALL ON TABLE netscaler_members FROM sysinfo;
GRANT ALL ON TABLE netscaler_members TO sysinfo;
GRANT SELECT ON TABLE netscaler_members TO sysinforo;


--
-- Name: netscaler_pools; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE netscaler_pools FROM PUBLIC;
REVOKE ALL ON TABLE netscaler_pools FROM sysinfo;
GRANT ALL ON TABLE netscaler_pools TO sysinfo;
GRANT SELECT ON TABLE netscaler_pools TO sysinforo;


--
-- Name: network_groups; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE network_groups FROM PUBLIC;
REVOKE ALL ON TABLE network_groups FROM sysinfo;
GRANT ALL ON TABLE network_groups TO sysinfo;
GRANT SELECT ON TABLE network_groups TO dcoaccess;


--
-- Name: network_mapping; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE network_mapping FROM PUBLIC;
REVOKE ALL ON TABLE network_mapping FROM sysinfo;
GRANT ALL ON TABLE network_mapping TO sysinfo;
GRANT SELECT ON TABLE network_mapping TO dcoaccess;


--
-- Name: os; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE os FROM PUBLIC;
REVOKE ALL ON TABLE os FROM sysinfo;
GRANT ALL ON TABLE os TO sysinfo;
GRANT SELECT ON TABLE os TO sysinforo;


--
-- Name: pci; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE pci FROM PUBLIC;
REVOKE ALL ON TABLE pci FROM sysinfo;
GRANT ALL ON TABLE pci TO sysinfo;
GRANT SELECT ON TABLE pci TO sysinforo;


--
-- Name: process; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE process FROM PUBLIC;
REVOKE ALL ON TABLE process FROM sysinfo;
GRANT ALL ON TABLE process TO sysinfo;
GRANT SELECT ON TABLE process TO sysinforo;


--
-- Name: scsi; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE scsi FROM PUBLIC;
REVOKE ALL ON TABLE scsi FROM sysinfo;
GRANT ALL ON TABLE scsi TO sysinfo;
GRANT SELECT ON TABLE scsi TO sysinforo;


--
-- Name: smartctl; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE smartctl FROM PUBLIC;
REVOKE ALL ON TABLE smartctl FROM postgres;
GRANT ALL ON TABLE smartctl TO postgres;
GRANT ALL ON TABLE smartctl TO sysinfo;
GRANT ALL ON TABLE smartctl TO sysinfo_asls_master;


--
-- Name: snag_server_definitions; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE snag_server_definitions FROM PUBLIC;
REVOKE ALL ON TABLE snag_server_definitions FROM sysinfo;
GRANT ALL ON TABLE snag_server_definitions TO sysinfo;
GRANT ALL ON TABLE snag_server_definitions TO sysinfo_asls_master;


--
-- Name: snag_server_mappings; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE snag_server_mappings FROM PUBLIC;
REVOKE ALL ON TABLE snag_server_mappings FROM sysinfo;
GRANT ALL ON TABLE snag_server_mappings TO sysinfo;
GRANT ALL ON TABLE snag_server_mappings TO sysinfo_asls_master;


--
-- Name: sysinfo_tags; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE sysinfo_tags FROM PUBLIC;
REVOKE ALL ON TABLE sysinfo_tags FROM sysinfo;
GRANT ALL ON TABLE sysinfo_tags TO sysinfo;
GRANT ALL ON TABLE sysinfo_tags TO sysinfo_asls_master;


--
-- Name: test_iface; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE test_iface FROM PUBLIC;
REVOKE ALL ON TABLE test_iface FROM sysinfo;
GRANT ALL ON TABLE test_iface TO sysinfo;
GRANT SELECT ON TABLE test_iface TO sysinforo;


--
-- Name: tiface; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE tiface FROM PUBLIC;
REVOKE ALL ON TABLE tiface FROM sysinfo;
GRANT ALL ON TABLE tiface TO sysinfo;
GRANT SELECT ON TABLE tiface TO sysinforo;


--
-- Name: update_payload; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE update_payload FROM PUBLIC;
REVOKE ALL ON TABLE update_payload FROM sysinfo;
GRANT ALL ON TABLE update_payload TO sysinfo;
GRANT ALL ON TABLE update_payload TO sysinfo_asls_master;


--
-- Name: update_queue; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE update_queue FROM PUBLIC;
REVOKE ALL ON TABLE update_queue FROM sysinfo;
GRANT ALL ON TABLE update_queue TO sysinfo;
GRANT ALL ON TABLE update_queue TO sysinfo_asls_master;


--
-- Name: vmware_uuids; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE vmware_uuids FROM PUBLIC;
REVOKE ALL ON TABLE vmware_uuids FROM sysinfo;
GRANT ALL ON TABLE vmware_uuids TO sysinfo;
GRANT SELECT ON TABLE vmware_uuids TO sysinforo;


--
-- Name: was_apps; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE was_apps FROM PUBLIC;
REVOKE ALL ON TABLE was_apps FROM sysinfo;
GRANT ALL ON TABLE was_apps TO sysinfo;
GRANT SELECT ON TABLE was_apps TO sysinforo;


--
-- Name: xen_dom0; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE xen_dom0 FROM PUBLIC;
REVOKE ALL ON TABLE xen_dom0 FROM sysinfo;
GRANT ALL ON TABLE xen_dom0 TO sysinfo;
GRANT SELECT ON TABLE xen_dom0 TO sysinforo;


--
-- Name: xen_pif; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE xen_pif FROM PUBLIC;
REVOKE ALL ON TABLE xen_pif FROM sysinfo;
GRANT ALL ON TABLE xen_pif TO sysinfo;
GRANT ALL ON TABLE xen_pif TO sysinfo_asls_sysinfo;


--
-- Name: xen_uuids; Type: ACL; Schema: public; Owner: sysinfo
--

REVOKE ALL ON TABLE xen_uuids FROM PUBLIC;
REVOKE ALL ON TABLE xen_uuids FROM sysinfo;
GRANT ALL ON TABLE xen_uuids TO sysinfo;
GRANT SELECT ON TABLE xen_uuids TO sysinforo;


--
-- PostgreSQL database dump complete
--

