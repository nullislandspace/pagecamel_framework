declare var nextSave: Uint8Array;
declare var hasnextSave: boolean;
declare var intervalhandler: any;
declare var LZString: {
    compress: (data: string) => string;
    decompress: (data: string) => string;
};
declare function dataConverter(): void;
