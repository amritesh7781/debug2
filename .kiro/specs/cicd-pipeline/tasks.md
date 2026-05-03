# Implementation Plan: CI/CD Pipeline Hardening

## Overview

Restructure the existing two-job GitHub Actions workflow into five discrete jobs (`lint → test → terraform-apply → build-push → deploy`), harden both Dockerfiles with multi-stage builds and HEALTHCHECK instructions, add Terraform S3 remote state with an AWS Academy fallback, and add post-deploy ECS stability verification. The `/api/health` route and `lint` job already exist and require no changes.

## Tasks

- [x] 1. Convert `Dockerfile.backend` to a multi-stage build with HEALTHCHECK
  - Add `AS builder` label to the existing `FROM node:22-alpine3.21` line
  - Add a second `FROM node:22-alpine3.21` runtime stage after the builder stage
  - In the runtime stage: copy `node_modules` from builder with `COPY --from=builder`, then copy `server/src/` and `server/database/`
  - Recreate `appuser` in the runtime stage (`addgroup` + `adduser` + `USER appuser`)
  - Add `EXPOSE 5001`
  - Add `HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD wget -qO- http://localhost:5001/api/health || exit 1`
  - Add `CMD ["node", "src/index.js"]`
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 7.1, 7.3, 7.4_

- [x] 2. Add HEALTHCHECK to `Dockerfile.frontend`
  - Insert `HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD wget -qO- http://localhost:80 || exit 1` before the end of the nginx stage in `Docker/Dockerfile.frontend`
  - _Requirements: 7.2, 7.3, 7.4_

- [x] 3. Add `backend "s3" {}` block to `terraform/main.tf`
  - Replace the existing comment-only backend section inside the `terraform {}` block with an empty `backend "s3" {}` block
  - Keep the comment explaining that values are supplied at init time via `-backend-config` flags
  - Verify `terraform fmt` passes on the updated file
  - _Requirements: 4.1_

- [x] 4. Restructure `.github/workflows/deploy.yml` — remove `AWS_REGION` from `env` block
  - Remove the `AWS_REGION: us-east-1` line from the workflow-level `env:` block
  - Keep `TF_VERSION`, `TF_IN_AUTOMATION`, `TF_VAR_subnet_ids`, and `TF_VAR_security_group_id` in the `env:` block
  - _Requirements: 5.1, 5.2_

- [x] 5. Add `test` job to `.github/workflows/deploy.yml`
  - Add a new `test` job with `needs: [lint]` and `runs-on: ubuntu-latest`
  - Step 1: `actions/checkout@v4`
  - Step 2: `actions/setup-node@v4` with `node-version: '22'`
  - Step 3: Backend — `npm ci` with `working-directory: server`
  - Step 4: Backend — `npx vitest run --reporter=junit --outputFile=test-results/junit.xml` with `working-directory: server`
  - Step 5: Backend — `actions/upload-artifact@v4` uploading `server/test-results/junit.xml` as `backend-test-results` with `if: always()` and `if-no-files-found: warn`
  - Step 6: Frontend — `npm ci` with `working-directory: client`
  - Step 7: Frontend — `npx vitest run --reporter=junit --outputFile=test-results/junit.xml` with `working-directory: client`
  - Step 8: Frontend — `actions/upload-artifact@v4` uploading `client/test-results/junit.xml` as `frontend-test-results` with `if: always()` and `if-no-files-found: warn`
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.5_

- [x] 6. Add `terraform-apply` job to `.github/workflows/deploy.yml`
  - Add a new `terraform-apply` job with `needs: [test]` and `runs-on: ubuntu-latest`
  - Step 1: `actions/checkout@v4`
  - Step 2: Validate `AWS_REGION` secret — `test -n "${{ secrets.AWS_REGION }}" || (echo "❌ Missing secret: AWS_REGION" && exit 1)`
  - Step 3: Validate remaining secrets — `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_SUBNET_ID`, `AWS_SECURITY_GROUP_ID`, `TF_STATE_BUCKET`
  - Step 4: `aws-actions/configure-aws-credentials@v4` using `secrets.AWS_REGION` (not `env.AWS_REGION`)
  - Step 5: `hashicorp/setup-terraform@v3` with `terraform_version: ${{ env.TF_VERSION }}`
  - Step 6: S3 backend setup script — attempt to create/verify the bucket with versioning (`put-bucket-versioning Status=Enabled`), AES256 encryption (`put-bucket-encryption`), and public-access-block; set `USE_S3=true` in `$GITHUB_ENV` on success; log a warning and leave `USE_S3=false` on failure (AWS Academy fallback); handle `us-east-1` bucket creation without `LocationConstraint`
  - Step 7: Terraform Init — if `USE_S3=true`, run with `-backend-config` flags for bucket, key (`shopsmart/terraform.tfstate`), region, and `encrypt=true`; otherwise run with `-backend=false`
  - Step 8: Terraform Import Existing Resources — same import logic as the current `deploy` job (ECR backend, ECR frontend, ECS cluster)
  - Step 9: Terraform Plan — `terraform plan -input=false -out=tfplan` with `TF_VAR_image_tag` and `TF_VAR_aws_region` set to `secrets.AWS_REGION`
  - Step 10: Terraform Apply — `terraform apply -input=false -auto-approve tfplan`
  - _Requirements: 3.1, 3.2, 3.3, 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3_

- [x] 7. Add `build-push` job to `.github/workflows/deploy.yml`
  - Add a new `build-push` job with `needs: [terraform-apply]` and `runs-on: ubuntu-latest`
  - Step 1: `actions/checkout@v4`
  - Step 2: Validate `AWS_REGION` secret
  - Step 3: `aws-actions/configure-aws-credentials@v4` using `secrets.AWS_REGION`
  - Step 4: `aws-actions/amazon-ecr-login@v2`
  - Step 5: Build and push backend image — same logic as current `deploy` job, replacing `env.AWS_REGION` with `secrets.AWS_REGION`
  - Step 6: Build and push frontend image — same logic as current `deploy` job, replacing `env.AWS_REGION` with `secrets.AWS_REGION`
  - _Requirements: 3.1, 3.3, 3.4, 3.5, 5.1, 5.3_

- [x] 8. Restructure `deploy` job in `.github/workflows/deploy.yml`
  - Change `needs` from `[lint]` to `[build-push]`
  - Remove all steps that are now in `terraform-apply` and `build-push` (AWS credentials setup, ECR login, Docker build/push, Terraform setup/init/import/plan/apply)
  - Step 1: `actions/checkout@v4`
  - Step 2: Validate `AWS_REGION` secret
  - Step 3: `aws-actions/configure-aws-credentials@v4` using `secrets.AWS_REGION`
  - Step 4: Force new deployment — backend (`aws ecs update-service --force-new-deployment --region "${{ secrets.AWS_REGION }}"`)
  - Step 5: Force new deployment — frontend (same pattern)
  - Step 6: Wait for backend stability — `timeout 300 aws ecs wait services-stable --cluster shopsmart-cluster --services shopsmart-backend-service --region "${{ secrets.AWS_REGION }}" || (echo "❌ Backend service failed to stabilize within 300s" && exit 1)`
  - Step 7: Wait for frontend stability — same pattern for `shopsmart-frontend-service`
  - Step 8: Deployment summary — echo block confirming region, commit SHA, and both services stable
  - _Requirements: 3.1, 3.4, 3.5, 5.1, 5.3, 8.1, 8.2, 8.3, 8.4_

- [x] 9. Checkpoint — verify the complete workflow structure
  - Confirm the workflow has exactly 5 jobs: `lint`, `test`, `terraform-apply`, `build-push`, `deploy`
  - Confirm `needs` chain: `test` needs `lint`, `terraform-apply` needs `test`, `build-push` needs `terraform-apply`, `deploy` needs `build-push`
  - Confirm `AWS_REGION` does not appear in any `env:` block and all region references use `${{ secrets.AWS_REGION }}`
  - Confirm both Dockerfiles contain `HEALTHCHECK` with `--interval`, `--timeout`, and `--retries`
  - Confirm `Dockerfile.backend` has two `FROM` stages
  - Confirm `terraform/main.tf` has a `backend "s3" {}` block
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Tasks are ordered by implementation dependency: Dockerfiles and Terraform first, then workflow restructuring
- The `/api/health` route already exists in `server/src/app.js` — no changes needed there
- `server/vitest.config.js` does not configure a reporter, so `--reporter=junit` CLI flags work without any config changes
- The `lint` job is unchanged and requires no tasks
- The existing Docker build+push logic in the `deploy` job is moved to `build-push`, not rewritten
