CREATE EXTENSION pg_trgm;

-- tune dynamicexternalfiles for LIKE searches on basepath
CREATE INDEX dynamicexternalfiles_basepath_idx1 ON dynamicexternalfiles USING GIN(basepath gin_trgm_ops);
CREATE INDEX dynamicexternalfiles_basepath_idx2 ON dynamicexternalfiles (basepath);
ANALYZE dynamicexternalfiles;

-- tune dynamicfiles for LIKE searches on basepath
CREATE INDEX dynamicfiles_basepath_idx1 ON dynamicfiles USING GIN(basepath gin_trgm_ops);
CREATE INDEX dynamicfiles_basepath_idx2 ON dynamicfiles (basepath);
ANALYZE dynamicfiles;

-- Firewall
CREATE INDEX firewall_permablock_idx1 ON firewall_permablock (ip_addr);
CREATE INDEX firewall_permablock_candidates_idx1 ON firewall_permablock_candidates (ip_addr);
ANALYZE firewall_permablock;
ANALYZE firewall_permablock_candidates;


