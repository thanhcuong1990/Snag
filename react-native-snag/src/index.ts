import Snag from './NativeSnag';

export function log(message: string): void {
  if (__DEV__) {
    Snag?.log(message);
  }
}

export default {
  log,
};
