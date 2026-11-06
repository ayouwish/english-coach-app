import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xEC00;
const TAG: string = 'AssetProbe';

/**
 * Asset Store 自检：登录页启动时跑一次 add→query→remove 探针，
 * 用于区分「本机安全存储根本不可用」和「业务读写逻辑问题」。
 *
 * 探针使用独立 alias（`ec_asset_probe`），不会影响 token / 记住密码。
 */
export class AssetProbe {
  static result: string = '未检测';

  static async run(): Promise<void> {
    const alias = 'ec_asset_probe';
    const secret = 'probe-' + Date.now().toString();
    const createMap = (): asset.AssetMap => {
      const map: asset.AssetMap = new Map();
      map.set(asset.Tag.ALIAS, AssetProbe.encode(alias));
      map.set(asset.Tag.SECRET, AssetProbe.encode(secret));
      return map;
    };
    try {
      // 先清掉上次残留
      await AssetProbe.remove(alias);
      await asset.add(createMap());
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, AssetProbe.encode(alias));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const rows: asset.AssetMap[] = await asset.query(query);
      if (rows.length === 0) {
        AssetProbe.result = '可写但读不到';
      } else {
        AssetProbe.result = '正常';
      }
      await AssetProbe.remove(alias);
    } catch (err) {
      const e = err as BusinessError;
      AssetProbe.result = '失败 code=' + e.code.toString();
      hilog.error(DOMAIN, TAG, 'probe failed code=%{public}d', e.code);
    }
  }

  static ok(): boolean {
    return AssetProbe.result === '正常';
  }

  private static async remove(alias: string): Promise<void> {
    const attrs: asset.AssetMap = new Map();
    attrs.set(asset.Tag.ALIAS, AssetProbe.encode(alias));
    try {
      await asset.remove(attrs);
    } catch (err) {
      // 不存在时忽略
    }
  }

  private static encode(value: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(value);
  }
}
