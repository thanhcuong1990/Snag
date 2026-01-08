import Snag from './NativeSnag';

export function log(message: string, level: string = 'info'): void {
  if (__DEV__) {
    Snag?.log(message, level);
  }
}

let hijacked = false;

export function hijackConsole(): void {
  if (hijacked || !__DEV__) return;
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

// Auto-initialize hijacking in dev mode
if (__DEV__) {
  hijackConsole();
}

export default {
  log,
  hijackConsole,
};
