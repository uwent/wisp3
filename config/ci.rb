# The same checks run locally (bin/ci) and on GitHub Actions (.github/workflows/ci.yml)
CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bundle exec standardrb"
  step "Style: Frontend", "pnpm format:check"
  step "Lint: Frontend", "pnpm lint"
  step "Types: Svelte/TypeScript", "pnpm check"
  step "Generated types and routes are current", "TYPELIZER=1 bin/rails typelizer:generate && git diff --exit-code app/frontend/types/serializers app/frontend/routes"

  step "Tests: frontend", "pnpm test"
  step "Tests: Rails", "bundle exec rspec"
  step "Tests: browser", "bin/e2e"
end
