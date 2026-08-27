function assert_has_fields(s, fields, prefix)

    for k = 1:numel(fields)
        f = fields{k};
        if ~isfield(s, f)
            error('%s.%s is missing.', prefix, f);
        end
    end

end
