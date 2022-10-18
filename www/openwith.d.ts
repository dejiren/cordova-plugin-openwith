
interface IntentItemDataDescriptor {
  uri: string;
  type: string;
  name?: string;
  path?: string;
  base64?: string;
  text?: string;
  utis?: string[];
}

interface OpenWithIntent {
  action: string;
  exit: boolean;
  items: IntentItemDataDescriptor[];
}

type OpenWithHandler = (intent: OpenWithIntent) => void;

interface CordovaOpenWith {
  init: (success: () => void, error: (err) => void) => void;
  addHandler: (handler: OpenWithHandler) => void;
  load: (
    dataDescriptor: IntentItemDataDescriptor,
    loadSuccessCallback: (base64: string, dataDescriptor: IntentItemDataDescriptor) => void,
    loadErrorCallback?: (err: Error, dataDescriptor: IntentItemDataDescriptor) => void,
  ) => void;
  exit: () => void;
  setVerbosity(level: string);
  DEBUG: string;
  INFO: string;
  WARN: string;
  ERROR: string;
}

interface Cordova {
  openwith?: CordovaOpenWith;
}
