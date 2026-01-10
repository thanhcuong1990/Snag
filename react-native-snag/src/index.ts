import Snag from './NativeSnag';

export function isEnabled(): boolean {
  return Snag?.isEnabled() ?? false;
}

export function log(message: string, level: string = 'info', tag: string = 'React Native'): void {
  if (__DEV__ || isEnabled()) {
    Snag?.log(message, level, tag);
  }
}

let hijacked = false;

export function hijackConsole(): void {
  if (hijacked || (!__DEV__ && !isEnabled())) return;
  hijacked = true;

  const levels: (keyof Console)[] = ['log', 'warn', 'error', 'info', 'debug'];
  
  levels.forEach((level) => {
    const original = console[level] as Function;
    (console[level] as any) = (...args: any[]) => {
      // Pass to Snag
      const message = args.map(arg => {
        if (typeof arg === 'object') {
          try {
            return JSON.stringify(arg, null, 2);
          } catch (e) {
            return String(arg);
          }
        }
        return String(arg);
      }).join(' ');
      
      let snagLevel = level.toString();
      if (snagLevel === 'log') snagLevel = 'info';
      
      log(message, snagLevel);
      
      // Call original
      original.apply(console, args);
    };
  });
}

// Note: We no longer auto-hijack the console because the native Snag libraries
// now handle console.log capture automatically via zero-config hooks.
// You can still call hijackConsole() manually if you want object inspection.

export default {
  log,
  isEnabled,
  hijackConsole,
};
