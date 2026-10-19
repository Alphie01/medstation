-- One KÜB/KT covers every pack size of a product; chunks are matched to
-- drugs by the folded product name prefix as well as by drug_id.
ALTER TABLE doc_chunks ADD COLUMN name_fold TEXT;
CREATE INDEX doc_chunks_name_fold ON doc_chunks (name_fold);
