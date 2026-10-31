import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiError, ApiErrorCode } from '../net/ApiError';

const DOMAIN: number = 0xEC00;
const TAG: string = 'File';

/**
 * 沙箱文件小工具：目录创建、原子写、递归删除。
 * 只用于应用私有目录（filesDir / cacheDir），不碰公共媒体库。
 */
export class FileUtil {
  static exists(path: string): boolean {
    if (path.length === 0) {
      return false;
    }
    try {
      return fileIo.accessSync(path);
    } catch (err) {
      return false;
    }
  }

  static ensureDir(dir: string): void {
    if (dir.length === 0) {
      throw ApiError.local(ApiErrorCode.INTERNAL_ERROR, '目录路径为空');
    }
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
    } catch (err) {
      // 并发创建时可能已被别的调用创建，再检查一次
      if (!fileIo.accessSync(dir)) {
        throw ApiError.local(ApiErrorCode.INTERNAL_ERROR, '无法创建目录：' + dir);
      }
    }
  }

  static sizeOf(path: string): number {
    try {
      return fileIo.statSync(path).size;
    } catch (err) {
      return 0;
    }
  }

  static remove(path: string): void {
    if (!FileUtil.exists(path)) {
      return;
    }
    try {
      fileIo.unlinkSync(path);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'unlink failed: %{public}s', e.message);
    }
  }

  /** 先写 `<dest>.part` 再 rename，避免留下半截文件。 */
  static writeBytesAtomic(destPath: string, bytes: Uint8Array): void {
    const slash = destPath.lastIndexOf('/');
    if (slash > 0) {
      FileUtil.ensureDir(destPath.substring(0, slash));
    }
    const tmpPath = destPath + '.part';
    FileUtil.remove(tmpPath);
    const file = fileIo.openSync(tmpPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      const buffer: ArrayBuffer = (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength)
        ? bytes.buffer as ArrayBuffer
        : bytes.slice().buffer as ArrayBuffer;
      fileIo.writeSync(file.fd, buffer);
    } finally {
      fileIo.closeSync(file);
    }
    FileUtil.remove(destPath);
    fileIo.renameSync(tmpPath, destPath);
  }

  /** 递归删除目录内容并删除自身；失败只记日志，不阻塞 UI。 */
  static removeDir(dir: string): void {
    if (!FileUtil.exists(dir)) {
      return;
    }
    try {
      const names = fileIo.listFileSync(dir);
      for (const name of names) {
        const child = dir + '/' + name;
        let isDir = false;
        try {
          isDir = fileIo.statSync(child).isDirectory();
        } catch (err) {
          isDir = false;
        }
        if (isDir) {
          FileUtil.removeDir(child);
        } else {
          FileUtil.remove(child);
        }
      }
      fileIo.rmdirSync(dir);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'removeDir failed: %{public}s', e.message);
    }
  }

  /** 启动时清理下载残留（*.part）。 */
  static removePartFiles(dir: string): void {
    if (!FileUtil.exists(dir)) {
      return;
    }
    try {
      const names = fileIo.listFileSync(dir);
      for (const name of names) {
        if (name.endsWith('.part')) {
          FileUtil.remove(dir + '/' + name);
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'removePartFiles failed');
    }
  }
}
