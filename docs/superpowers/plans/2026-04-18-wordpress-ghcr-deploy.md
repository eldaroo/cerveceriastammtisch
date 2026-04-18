# WordPress GHCR Deploy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SSH-based file sync with a build-and-push deployment flow that publishes a custom WordPress image and a custom MariaDB init image to GHCR, then deploys both images through Nomad.

**Architecture:** The site repo becomes the source of truth for the WordPress runtime image, the preloaded `wp-content` tree, and the database restore payload. GitHub Actions builds and pushes two images on every deploy: one WordPress image containing the site files, and one MariaDB image containing the restore SQL. Nomad then pulls those images directly, which removes the need to copy files onto the Nomad host during each deployment.

**Tech Stack:** Docker, GitHub Actions, GHCR, Nomad, WordPress, MariaDB, Traefik

---

### Task 1: Build reproducible container images from the repo

**Files:**
- Create: `Dockerfile`
- Create: `nomad/mariadb.Dockerfile`
- Create: `.dockerignore`

- [ ] **Step 1: Define the WordPress runtime image**

The image should start from `wordpress:php8.2-apache`, copy the site tree from `public/` into `/var/www/html`, and leave `wp-config.php` out of the image so the environment still injects database credentials at runtime.

```dockerfile
FROM wordpress:php8.2-apache

COPY public/ /var/www/html/

RUN rm -f /var/www/html/wp-config.php \
  && chown -R www-data:www-data /var/www/html
```

- [ ] **Step 2: Define the MariaDB init image**

The MariaDB image should start from `mariadb:10.11` and copy the restored SQL into the official init directory so the database seeds itself on first boot.

```dockerfile
FROM mariadb:10.11

COPY nomad/dist/db-init/01-restore.sql /docker-entrypoint-initdb.d/01-restore.sql
```

- [ ] **Step 3: Reduce build context size**

Exclude the Git metadata, local GitHub workflow artifacts, and the generated `nomad/dist/` output from both image builds, but keep the WordPress source tree and the SQL dump available to the workflow.

```gitignore
.git
.github
nomad/dist/
```

- [ ] **Step 4: Verify the Dockerfiles parse**

Run:

```bash
docker build -f Dockerfile -t cerveceria-wordpress:test .
docker build -f nomad/mariadb.Dockerfile -t cerveceria-mariadb:test .
```

Expected: both builds should complete far enough to validate syntax and copy paths; the first build may be large because the repo contains the full WordPress tree.

### Task 2: Rework the Nomad job to consume built images

**Files:**
- Modify: `nomad/wordpress.nomad.hcl`
- Modify: `nomad/wordpress.nomad.vars.hcl.example`
- Modify: `nomad/README.md`

- [ ] **Step 1: Replace the base-image assumptions with image variables**

The job should accept `wordpress_image` and `mariadb_image` variables and use those values in the task configs instead of hardcoded upstream images.

```hcl
variable "wordpress_image" {
  type = string
}

variable "mariadb_image" {
  type = string
}
```

- [ ] **Step 2: Remove host-volume sync requirements from the WordPress task**

The WordPress task should no longer mount `wp-content` from the host. It should run from the built image and keep only the database service dependency.

```hcl
task "wordpress" {
  driver = "docker"

  config {
    image = var.wordpress_image
    ports = ["http"]
  }
}
```

- [ ] **Step 3: Keep MariaDB persistence only for the database data**

The MariaDB task should still mount a persistent data volume, but the restore SQL should come from the image instead of a host init directory.

```hcl
task "db" {
  driver = "docker"

  config {
    image = var.mariadb_image
    ports = ["db"]
  }
}
```

- [ ] **Step 4: Update the example vars file and README**

Document the new deploy contract with image refs such as `ghcr.io/eldaroo/cerveceriastammtisch-wordpress:latest` and `ghcr.io/eldaroo/cerveceriastammtisch-mariadb:latest`, and remove the one-time SSH copy instructions.

- [ ] **Step 5: Verify the HCL still validates conceptually**

Run:

```bash
nomad job validate nomad/wordpress.nomad.hcl
```

Expected: the job should validate once Nomad is available locally.

### Task 3: Rewrite GitHub Actions to build and publish images

**Files:**
- Modify: `.github/workflows/deploy.yml`

- [ ] **Step 1: Remove the SSH sync path**

Delete the SSH setup, the `rsync` steps, and the temporary host-volume preparation.

- [ ] **Step 2: Build and push the WordPress image**

Use `docker/login-action`, `docker/setup-buildx-action`, and `docker/build-push-action` to publish the WordPress image to GHCR with `latest` and `${{ github.sha }}` tags.

```yaml
- name: Build and push WordPress image
  uses: docker/build-push-action@v6
  with:
    context: .
    file: Dockerfile
    push: true
    tags: |
      ghcr.io/${{ github.repository_owner }}/cerveceriastammtisch-wordpress:latest
      ghcr.io/${{ github.repository_owner }}/cerveceriastammtisch-wordpress:${{ github.sha }}
```

- [ ] **Step 3: Build and push the MariaDB init image**

Publish the MariaDB image from `nomad/mariadb.Dockerfile` using the same tag strategy.

```yaml
- name: Build and push MariaDB image
  uses: docker/build-push-action@v6
  with:
    context: .
    file: nomad/mariadb.Dockerfile
    push: true
    tags: |
      ghcr.io/${{ github.repository_owner }}/cerveceriastammtisch-mariadb:latest
      ghcr.io/${{ github.repository_owner }}/cerveceriastammtisch-mariadb:${{ github.sha }}
```

- [ ] **Step 4: Generate Nomad vars from the pushed image tags**

The workflow should write a temporary vars file that points `wordpress_image` and `mariadb_image` at the pushed GHCR tags and still injects the database credentials and site URL.

```bash
python3 - <<'PY'
from pathlib import Path
Path("vars.hcl").write_text(
    'wordpress_image = "ghcr.io/OWNER/cerveceriastammtisch-wordpress:SHA"\n'
    'mariadb_image = "ghcr.io/OWNER/cerveceriastammtisch-mariadb:SHA"\n'
)
PY
```

- [ ] **Step 5: Deploy the Nomad job**

Keep `nomad job run` as the final step, using the image-based vars file.

- [ ] **Step 6: Verify the workflow syntax**

Run:

```bash
python -c "import yaml, pathlib; yaml.safe_load(pathlib.Path('.github/workflows/deploy.yml').read_text(encoding='utf-8')); print('ok')"
```

Expected: `ok`

### Task 4: Clean up docs and confirm the new deploy path

**Files:**
- Modify: `README.md`
- Modify: `nomad/README.md`

- [ ] **Step 1: Document the new deployment flow**

Explain that GitHub Actions builds and publishes both images, Nomad pulls them, and no per-deploy SSH copy is needed anymore.

- [ ] **Step 2: State the operational tradeoff**

Document that the site is now image-driven, so changes to files in `public/` require a new GitHub deploy rather than a manual server-side edit.

- [ ] **Step 3: Run the repo-level checks**

Run:

```bash
git diff --check
git status -sb
```

Expected: no whitespace errors and only the intended files changed.
