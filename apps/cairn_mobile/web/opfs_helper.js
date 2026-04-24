/**
 * OPFS (Origin Private File System) helper for flutter_gemma streaming mode.
 *
 * flutter_gemma binds to window.flutterGemmaOPFS when WebStorageMode.streaming
 * is enabled. Without this helper, startup fails before Flutter can render.
 */
window.flutterGemmaOPFS = {
  async isModelCached(filename) {
    try {
      const opfs = await navigator.storage.getDirectory();
      await opfs.getFileHandle(filename);
      return true;
    } catch (_) {
      return false;
    }
  },

  async getCachedModelSize(filename) {
    try {
      const opfs = await navigator.storage.getDirectory();
      const handle = await opfs.getFileHandle(filename);
      const file = await handle.getFile();
      return file.size;
    } catch (_) {
      return null;
    }
  },

  async downloadToOPFS(url, filename, authToken, onProgress, abortSignal) {
    let writable = null;
    let reader = null;

    try {
      const estimate = await navigator.storage.estimate();
      const fetchOptions = {};
      if (authToken) {
        fetchOptions.headers = { Authorization: `Bearer ${authToken}` };
      }
      if (abortSignal) {
        fetchOptions.signal = abortSignal;
      }

      const response = await fetch(url, fetchOptions);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const contentLength = parseInt(
        response.headers.get("content-length") || "0",
        10,
      );
      if (estimate.quota && contentLength > 0) {
        const availableSpace = estimate.quota - (estimate.usage || 0);
        if (contentLength > availableSpace) {
          throw new Error(
            `Insufficient storage: need ${(contentLength / 1e9).toFixed(2)}GB, ` +
              `available ${(availableSpace / 1e9).toFixed(2)}GB`,
          );
        }
      }

      const opfs = await navigator.storage.getDirectory();
      const fileHandle = await opfs.getFileHandle(filename, { create: true });
      writable = await fileHandle.createWritable();
      reader = response.body.getReader();

      let bytesReceived = 0;
      let lastProgressPercent = 0;
      while (true) {
        if (abortSignal?.aborted) {
          throw new DOMException("Download aborted", "AbortError");
        }

        const { done, value } = await reader.read();
        if (done) break;

        await writable.write(value);
        bytesReceived += value.length;

        if (contentLength > 0) {
          const progressPercent = Math.round(
            (bytesReceived / contentLength) * 100,
          );
          if (progressPercent !== lastProgressPercent) {
            onProgress(progressPercent);
            lastProgressPercent = progressPercent;
          }
        }
      }

      await writable.close();
      writable = null;
      return true;
    } catch (error) {
      if (reader) {
        try {
          await reader.cancel();
        } catch (_) {}
      }
      if (writable) {
        try {
          await writable.abort();
        } catch (_) {}
      }
      if (error.name === "AbortError") {
        try {
          const opfs = await navigator.storage.getDirectory();
          await opfs.removeEntry(filename);
        } catch (_) {}
      }
      throw error;
    }
  },

  async getStreamReader(filename) {
    try {
      const opfs = await navigator.storage.getDirectory();
      const handle = await opfs.getFileHandle(filename);
      const file = await handle.getFile();
      return file.stream().getReader();
    } catch (_) {
      throw new Error(`Model not found in OPFS: ${filename}`);
    }
  },

  async deleteModel(filename) {
    const opfs = await navigator.storage.getDirectory();
    await opfs.removeEntry(filename);
  },

  async getStorageStats() {
    const estimate = await navigator.storage.estimate();
    return {
      usage: estimate.usage || 0,
      quota: estimate.quota || 0,
    };
  },

  async clearAll() {
    const opfs = await navigator.storage.getDirectory();
    let count = 0;
    for await (const [name, handle] of opfs.entries()) {
      if (handle.kind === "file") {
        await opfs.removeEntry(name);
        count++;
      }
    }
    return count;
  },
};
