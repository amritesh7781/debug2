# Requirements Document

## Introduction

This document captures the requirements for completing and hardening the ShopSmart CI/CD pipeline. A partial pipeline already exists in `.github/workflows/deploy.yml` with a `lint` job (Terraform fmt/validate, hadolint) and a `deploy` job (Docker build+push, Terraform apply, ECS force-new-deployment). The requirements below focus exclusively on what is **missing or incorrect** relative to the rubric, without re-specifying what already works correctly.

The four gap areas are:
1. **Automated testing** — no test execution step exists in the pipeline.
2. **Pipeline job ordering** — Docker build currently runs before Terraform apply; the required order is Tests → Terraform Apply → Docker Build & Push → ECS Deploy.
3. **Terraform remote state** — the pipeline uses local state; an S3 backend with versioning, encryption, and public-access blocking is required (with an AWS Academy compatibility fallback).
4. **Dockerfile hardening** — `Dockerfile.backend` is missing a multi-stage build and a `HEALTHCHECK` instruction; `Dockerfile.frontend` already uses multi-stage but is missing a `HEALTHCHECK`.
5. **Post-deploy verification** — no stability check is performed after ECS services are updated.
6. **AWS_REGION secret** — the region is currently hardcoded as an `env` var; the rubric requires it to be sourced from a GitHub Secret.

---

## Glossary

- **Pipeline**: The GitHub Actions workflow defined in `.github/workflows/deploy.yml`.
- **CI_System**: The GitHub Actions runner executing the Pipeline.
- **Test_Runner**: The Vitest process that executes unit and integration tests.
- **Playwright_Runner**: The Playwright process that executes frontend end-to-end tests.
- **Terraform**: The infrastructure-as-code tool managing AWS resources.
- **S3_Backend**: An AWS S3 bucket used to store Terraform remote state.
- **ECR**: Amazon Elastic Container Registry, where Docker images are stored.
- **ECS**: Amazon Elastic Container Service (Fargate), where containers are deployed.
- **ECS_Service**: A named Fargate service (`shopsmart-backend-service` or `shopsmart-frontend-service`) running inside the ECS cluster.
- **Dockerfile_Backend**: `Docker/Dockerfile.backend` — the build file for the backend container.
- **Dockerfile_Frontend**: `Docker/Dockerfile.frontend` — the build file for the frontend container.
- **JUnit_Report**: An XML test report in JUnit format, consumable by GitHub Actions test summary.
- **GitHub_Secret**: A repository-level encrypted secret accessible via `${{ secrets.NAME }}` in the Pipeline.
- **AWS_Academy**: The restricted AWS learning environment used for this project, which may not support S3 backend for Terraform state.

---

## Requirements

### Requirement 1: Automated Backend Testing

**User Story:** As a developer, I want the pipeline to run backend unit and integration tests automatically on every push, so that regressions are caught before any infrastructure or deployment steps run.

#### Acceptance Criteria

1. WHEN a push to `main` is made, THE CI_System SHALL execute the backend test suite using `vitest run` inside the `server/` directory before the Terraform apply step runs.
2. WHEN the backend test suite completes, THE Test_Runner SHALL produce a JUnit XML report and upload it as a GitHub Actions artifact.
3. IF any backend test fails, THEN THE CI_System SHALL fail the pipeline and SHALL NOT proceed to the Terraform apply, Docker build, or ECS deploy steps.
4. THE CI_System SHALL install backend Node.js dependencies using `npm ci` in the `server/` directory before invoking the Test_Runner.

---

### Requirement 2: Automated Frontend Unit Testing

**User Story:** As a developer, I want the pipeline to run frontend unit tests automatically on every push, so that UI regressions are caught before deployment.

#### Acceptance Criteria

1. WHEN a push to `main` is made, THE CI_System SHALL execute the frontend unit test suite using `vitest run` inside the `client/` directory before the Terraform apply step runs.
2. WHEN the frontend unit test suite completes, THE Test_Runner SHALL produce a JUnit XML report and upload it as a GitHub Actions artifact.
3. IF any frontend unit test fails, THEN THE CI_System SHALL fail the pipeline and SHALL NOT proceed to the Terraform apply, Docker build, or ECS deploy steps.
4. THE CI_System SHALL install frontend Node.js dependencies using `npm ci` in the `client/` directory before invoking the Test_Runner.

---

### Requirement 3: Pipeline Job Execution Order

**User Story:** As a developer, I want the pipeline jobs to run in the correct sequence, so that broken code is never built into a Docker image and untested images are never deployed to infrastructure.

#### Acceptance Criteria

1. THE Pipeline SHALL execute jobs in the following order: `lint` → `test` → `terraform-apply` → `build-push` → `deploy`.
2. WHEN the `test` job has not completed successfully, THE CI_System SHALL NOT start the `terraform-apply` job.
3. WHEN the `terraform-apply` job has not completed successfully, THE CI_System SHALL NOT start the `build-push` job.
4. WHEN the `build-push` job has not completed successfully, THE CI_System SHALL NOT start the `deploy` job.
5. THE Pipeline SHALL express these ordering constraints using GitHub Actions `needs` declarations on each dependent job.

---

### Requirement 4: Terraform S3 Remote State

**User Story:** As a developer, I want Terraform state stored remotely in S3, so that state is shared across pipeline runs and not lost between executions.

#### Acceptance Criteria

1. THE Terraform configuration SHALL declare an S3 backend with a globally unique bucket name, versioning enabled, server-side encryption enabled, and public access blocked.
2. WHEN the S3 backend bucket does not exist, THE CI_System SHALL create it with versioning, encryption, and public-access-block settings applied before running `terraform init`.
3. WHEN the AWS Academy environment does not support S3 backend, THE CI_System SHALL fall back to local state and SHALL log a warning message indicating that remote state is unavailable.
4. THE S3_Backend bucket name SHALL be configurable via a GitHub Secret named `TF_STATE_BUCKET` so that it is not hardcoded in the workflow file.

---

### Requirement 5: AWS Region Sourced from GitHub Secret

**User Story:** As a developer, I want the AWS region to be stored as a GitHub Secret rather than hardcoded in the workflow, so that the pipeline configuration follows the project's secret management convention.

#### Acceptance Criteria

1. THE Pipeline SHALL read the AWS region exclusively from the GitHub Secret `AWS_REGION` using `${{ secrets.AWS_REGION }}`.
2. THE Pipeline SHALL NOT define `AWS_REGION` as a hardcoded `env` variable at the workflow or job level.
3. WHEN the `AWS_REGION` secret is absent or empty, THE CI_System SHALL fail the pipeline with a descriptive error message before any AWS API calls are made.

---

### Requirement 6: Dockerfile Backend Multi-Stage Build

**User Story:** As a developer, I want `Dockerfile.backend` to use a multi-stage build, so that the final production image contains only runtime dependencies and no build-time tooling.

#### Acceptance Criteria

1. THE Dockerfile_Backend SHALL define a `builder` stage that installs all Node.js dependencies (including dev dependencies if needed for any build step).
2. THE Dockerfile_Backend SHALL define a separate final stage that copies only the production artifacts from the `builder` stage.
3. THE Dockerfile_Backend SHALL run `npm ci --omit=dev` in the final stage (or copy only the production `node_modules` from the builder stage) so that dev dependencies are excluded from the final image.
4. THE Dockerfile_Backend SHALL preserve the existing non-root `appuser` in the final stage.

---

### Requirement 7: Dockerfile HEALTHCHECK Instructions

**User Story:** As a developer, I want both Dockerfiles to include a `HEALTHCHECK` instruction, so that ECS and Docker can detect and replace unhealthy containers automatically.

#### Acceptance Criteria

1. THE Dockerfile_Backend SHALL include a `HEALTHCHECK` instruction that probes the backend HTTP endpoint on port 5001 at a defined interval.
2. THE Dockerfile_Frontend SHALL include a `HEALTHCHECK` instruction that probes the Nginx HTTP endpoint on port 80 at a defined interval.
3. WHEN the health check command exits with a non-zero status code for a configurable number of consecutive retries, THE container runtime SHALL mark the container as unhealthy.
4. THE `HEALTHCHECK` instruction in each Dockerfile SHALL specify `--interval`, `--timeout`, and `--retries` values.

---

### Requirement 8: Post-Deploy ECS Service Stability Verification

**User Story:** As a developer, I want the pipeline to verify that ECS services reach a stable running state after deployment, so that a failed rollout is detected and reported immediately rather than silently.

#### Acceptance Criteria

1. WHEN the ECS force-new-deployment commands complete, THE CI_System SHALL wait for both `shopsmart-backend-service` and `shopsmart-frontend-service` to reach a stable state using `aws ecs wait services-stable`.
2. WHEN an ECS service does not reach a stable state within 300 seconds, THE CI_System SHALL fail the pipeline step and report which service failed to stabilize.
3. THE CI_System SHALL check stability for the backend service and the frontend service as separate, sequential steps so that a failure in one is clearly attributed.
4. WHEN both services reach a stable state, THE CI_System SHALL log a confirmation message indicating successful deployment.
