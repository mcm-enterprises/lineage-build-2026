# Robust Docker Build (Pixel 8 Pro)

This is a **self-contained, fault-tolerant** Docker environment for building LineageOS. It is designed to handle:
*   Slow external drive I/O.
*   "Repo sync" failures (network or lock files).
*   Host permission mismatches (UID/GID).
*   Proprietary driver downloads (TheMuppets).

## Directory Structure
*   `docker_env/`: Contains the Dockerfile and scripts.
*   `docker_source/`: Contains the massive downloaded data (Source, Cache, Zips).

## How to Run

### 0. Prerequisite: Switch to Docker Engine
Do **NOT** use Docker Desktop (it has poor I/O performance on Linux). Use the native Docker Engine.

```bash
# Check current context
docker context ls

# Switch to native engine (if mostly seeing 'desktop-linux')
docker context use default
```

1.  **Enter the Docker folder:**
    ```bash
    cd docker_env
    ```

2.  **Build the Image:**
    ```bash
    docker compose build
    ```

3.  **Start the Build (Detached):**
    ```bash
    docker compose up -d
    ```

4.  **Monitor Progress:**
    ```bash
    docker compose logs -f
    ```

## Features
*   **Auto-Healing Sync:** If `repo sync` crashes, the container automatically cleans lock files and retries (up to 100 times).
*   **Permissions:** The container automatically detects that you own the `docker_source` folder and creates an internal user to match. No `chown` needed.
*   **Muppets:** Automatically configures vendor manifests to fetch blobs from TheMuppets (if key matches).
    *   *Note:* If TheMuppets is missing files for 22.1, you may need to copy `vendor/google` from your baremetal build into `docker_source/lineage/vendor/google`.
