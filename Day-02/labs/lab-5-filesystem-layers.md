# Lab 5: Mounting OverlayFS Manually (How Container Storage Works)

In this lab, you will manually construct an OverlayFS mount. This is the underlying technology container engines use to merge read-only image layers and a writable container layer into a single unified directory.

---

## Step 1: Create the Overlay Directories
We will create four directories to represent the different layers of our container filesystem:
```bash
mkdir -p /tmp/overlay-lab/{lower1,lower2,upper,work,merged}
cd /tmp/overlay-lab
```
*   `lower1`: Bottom read-only layer (mimicking base OS layer).
*   `lower2`: Middle read-only layer (mimicking application installation layer).
*   `upper`: Top writable layer (mimicking the container run-time writes).
*   `work`: Kernel workspace directory.
*   `merged`: The actual root filesystem `/` target seen by the container processes.

---

## Step 2: Populate the Image Layers (lowerdir)
Let's add files to our read-only image layers to represent base configs:
```bash
# Add files to bottom layer
echo "base OS configuration" > lower1/os-config.txt
echo "original web server config" > lower1/web.conf

# Add files to middle layer (some overwriting the bottom layer)
echo "v1.0.0 app code" > lower2/app.js
echo "customized web server config" > lower2/web.conf
```
Note that `web.conf` exists in both layers. In OverlayFS, upper layers overwrite lower layers.

---

## Step 3: Mount the OverlayFS
Now, mount the directories together using the `mount` command with the filesystem type `overlay`:
```bash
sudo mount -t overlay overlay \
  -o lowerdir=lower2:lower1,upperdir=upper,workdir=work \
  merged/
```
*   **What this means:** We instruct the kernel to mount an overlay filesystem onto the target folder `merged/`. The layers stack from right-to-left in the `lowerdir` parameter (`lower2` overlays `lower1`). `upperdir` acts as the writable layer.

---

## Step 4: Inspect the Merged View
Inspect the contents of the `merged` directory:
```bash
ls -la merged/
```
*Expected Output:*
```text
os-config.txt   # From lower1
app.js          # From lower2
web.conf        # From lower2 (since lower2 takes precedence over lower1)
```
Check the contents of `merged/web.conf`:
```bash
cat merged/web.conf
# Output: customized web server config (from lower2)
```

---

## Step 5: Test Copy-on-Write (CoW)
What happens if we modify a file in the read-only layer? Let's edit `os-config.txt` inside the `merged/` directory:
```bash
echo "modified config" >> merged/os-config.txt
```
Now, verify the files inside the source directories:
1.  **Check `lower1/os-config.txt` (the original):**
    ```bash
    cat lower1/os-config.txt
    # Output: base OS configuration
    # (Unchanged!)
    ```
2.  **Check `upper/os-config.txt` (the writable layer):**
    ```bash
    cat upper/os-config.txt
    # Output:
    # base OS configuration
    # modified config
    ```
### System Insight
The kernel executed a **Copy-on-Write**. It copied the file from the read-only `lower1` to the writable `upper` directory, and then applied the modifications. In `merged/`, you see the modified file, but the underlying base image layer is safe and untouched.

---

## Step 6: Test File Deletion (Whiteouts)
What happens when you delete a file that belongs to a read-only image layer?
```bash
rm merged/app.js
# Verify it disappeared from the merged view
ls -la merged/
```
You will notice `app.js` is gone from `merged/`. But wait—can we delete it from the read-only `lower2/` directory? Let's check:
```bash
ls -la lower2/
# Output: app.js still exists!
```
How did the kernel hide the file from the `merged` directory? Let's check the writable `upper` directory:
```bash
ls -la upper/
```
*Expected Output:*
```text
c--------- 1 root root 0, 0 May 24 15:30 app.js
```
Notice that `upper/app.js` was created as a **character device** with major/minor device numbers `0,0` (a **whiteout file**). When OverlayFS mounts, it interprets this character device as a mask, completely hiding `app.js` from the container's merged view.

---

## Clean Up
Unmount the overlay filesystem and clean up directories:
```bash
sudo umount merged/
cd /tmp
sudo rm -rf /tmp/overlay-lab
```
