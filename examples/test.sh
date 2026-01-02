bq query --nouse_legacy_sql \
"SELECT table_name FROM \`rituals-test.dna.INFORMATION_SCHEMA.TABLES\` WHERE table_name LIKE 'DimLegalEntity__%'" |
while read TABLE_NAME; do
  [[ "$TABLE_NAME" == "table_name" ]] && continue  # skip header
  echo "Setting expiration for $TABLE_NAME"
done