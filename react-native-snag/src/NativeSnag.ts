import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  log(message: string): void;
}

export default TurboModuleRegistry.get<Spec>(
  'Snag'
) as Spec | null;
