#!/bin/zsh
# Re-runs the full load + evaluation for each configuration and stores the output in results/.
export PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH
cd "$(dirname "$0")/../data" || exit 1
mkdir -p ../results
run() {  # name, extra psql -v args
  name=$1; shift
  psql -q -d linklogic -f ../sql/01_schema.sql -f ../sql/02_resolver.sql >/dev/null 2>&1
  psql -q -d linklogic "$@" -f ../sql/03_load_and_run.sql >/dev/null 2>&1
  psql -d linklogic -f ../sql/04_evaluate.sql > ../results/$name.txt
  echo "== $name"; head -4 ../results/$name.txt | tail -2
}
run alias_on_t075  -v use_alias=1 -v t_auto=0.75
run alias_off_t075 -v use_alias=0 -v t_auto=0.75
run alias_on_t060  -v use_alias=1 -v t_auto=0.60
run alias_on_t085  -v use_alias=1 -v t_auto=0.85
run alias_on_t095  -v use_alias=1 -v t_auto=0.95
