#!/usr/bin/env bash
set -euo pipefail

bundle install
bin/rails assets:precompile
# Free Render services have no pre-deploy hook. Migrate during the build.
# Import shared reference data without creating a demo account.
bin/rails db:migrate
bin/rails jozu:import
