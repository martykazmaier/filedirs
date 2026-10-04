{ Windows implementation of the platform layer used by filedirs.pas. }

const
  Kernel32Dll = 'kernel32.dll';
  MdInvalidAttr = DWORD($FFFFFFFF);
  MdAttrDirectory = $10;
  MdAttrReparse = $400;
  MdGenericRead = DWORD($80000000);
  MdGenericWrite = DWORD($40000000);
  MdShareRead = 1;
  MdShareWrite = 2;
  MdShareDelete = 4;
  MdCreateAlways = 2;
  MdOpenExisting = 3;
  MdFileAttrNormal = $80;
  MdMoveReplace = 1;
  MdMoveWriteThrough = 8;
  MdStdOutput = DWORD($FFFFFFF5);
  MdStdError = DWORD($FFFFFFF4);
  MdNoBestFit = $400;
  MdBackupSemantics = $02000000;
  MdSymlinkDirectory = 1;
  MdSymlinkUnprivileged = 2;
  MdErrorPrivilegeNotHeld = 1314;
  MdErrorInvalidParameter = 87;

function MdGetFileAttributesW(p: PWideChar): DWORD; stdcall; external Kernel32Dll name 'GetFileAttributesW';
function MdCreateFileW(p: PWideChar; access, share: DWORD; sec: Pointer; disposition, flags: DWORD; template: THandle): THandle; stdcall; external Kernel32Dll name 'CreateFileW';
function MdReadFile(h: THandle; buf: Pointer; n: DWORD; done: PDWORD; ov: Pointer): BOOL; stdcall; external Kernel32Dll name 'ReadFile';
function MdWriteFile(h: THandle; buf: Pointer; n: DWORD; done: PDWORD; ov: Pointer): BOOL; stdcall; external Kernel32Dll name 'WriteFile';
function MdGetFileSize(h: THandle; high: PDWORD): DWORD; stdcall; external Kernel32Dll name 'GetFileSize';
function MdFlushFileBuffers(h: THandle): BOOL; stdcall; external Kernel32Dll name 'FlushFileBuffers';
function MdCloseHandle(h: THandle): BOOL; stdcall; external Kernel32Dll name 'CloseHandle';
function MdDeleteFileW(p: PWideChar): BOOL; stdcall; external Kernel32Dll name 'DeleteFileW';
function MdMoveFileExW(src, dst: PWideChar; flags: DWORD): BOOL; stdcall; external Kernel32Dll name 'MoveFileExW';
function MdCopyFileW(src, dst: PWideChar; failIfExists: BOOL): BOOL; stdcall; external Kernel32Dll name 'CopyFileW';
function MdFindFirstFileW(p: PWideChar; data: Pointer): THandle; stdcall; external Kernel32Dll name 'FindFirstFileW';
function MdFindNextFileW(h: THandle; data: Pointer): BOOL; stdcall; external Kernel32Dll name 'FindNextFileW';
function MdFindClose(h: THandle): BOOL; stdcall; external Kernel32Dll name 'FindClose';
function MdGetFullPathNameW(p: PWideChar; n: DWORD; buf: PWideChar; filePart: Pointer): DWORD; stdcall; external Kernel32Dll name 'GetFullPathNameW';
function MdGetLongPathNameW(p: PWideChar; buf: PWideChar; n: DWORD): DWORD; stdcall; external Kernel32Dll name 'GetLongPathNameW';
function MdGetShortPathNameW(p: PWideChar; buf: PWideChar; n: DWORD): DWORD; stdcall; external Kernel32Dll name 'GetShortPathNameW';
function MdGetCurrentDirectoryW(n: DWORD; buf: PWideChar): DWORD; stdcall; external Kernel32Dll name 'GetCurrentDirectoryW';
function MdGetEnvironmentVariableW(name, buf: PWideChar; n: DWORD): DWORD; stdcall; external Kernel32Dll name 'GetEnvironmentVariableW';
function MdGetCommandLineW: PWideChar; stdcall; external Kernel32Dll name 'GetCommandLineW';
function MdLocalFree(h: Pointer): Pointer; stdcall; external Kernel32Dll name 'LocalFree';
function MdGetStdHandle(n: DWORD): THandle; stdcall; external Kernel32Dll name 'GetStdHandle';
function MdGetConsoleMode(h: THandle; mode: PDWORD): BOOL; stdcall; external Kernel32Dll name 'GetConsoleMode';
function MdWriteConsoleW(h: THandle; buf: Pointer; n: DWORD; done: PDWORD; reserved: Pointer): BOOL; stdcall; external Kernel32Dll name 'WriteConsoleW';
function MdGetLastError: DWORD; stdcall; external Kernel32Dll name 'GetLastError';
function MdIsValidCodePage(cp: UINT): BOOL; stdcall; external Kernel32Dll name 'IsValidCodePage';
function MdWideCharToMultiByte(cp: UINT; flags: DWORD; src: PWideChar; srcLen: Integer; dst: PAnsiChar; dstLen: Integer; defChar: PAnsiChar; usedDef: Pointer): Integer; stdcall; external Kernel32Dll name 'WideCharToMultiByte';
function MdMultiByteToWideChar(cp: UINT; flags: DWORD; src: PAnsiChar; srcLen: Integer; dst: PWideChar; dstLen: Integer): Integer; stdcall; external Kernel32Dll name 'MultiByteToWideChar';
function MdCharLowerBuffW(p: PWideChar; n: DWORD): DWORD; stdcall; external 'user32.dll' name 'CharLowerBuffW';
function MdCharUpperBuffW(p: PWideChar; n: DWORD): DWORD; stdcall; external 'user32.dll' name 'CharUpperBuffW';
function MdCreateSymbolicLinkW(link, target: PWideChar; flags: DWORD): ByteBool; stdcall; external Kernel32Dll name 'CreateSymbolicLinkW';
function MdGetFinalPathNameByHandleW(h: THandle; buf: PWideChar; n, flags: DWORD): DWORD; stdcall; external Kernel32Dll name 'GetFinalPathNameByHandleW';
function MdCreateDirectoryW(p: PWideChar; sec: Pointer): BOOL; stdcall; external Kernel32Dll name 'CreateDirectoryW';
function MdRemoveDirectoryW(p: PWideChar): BOOL; stdcall; external Kernel32Dll name 'RemoveDirectoryW';
function MdCommandLineToArgvW(cmd: PWideChar; numArgs: PLongInt): PPWideChar; stdcall; external 'shell32.dll' name 'CommandLineToArgvW';

function ErrText(code: DWORD): UnicodeString;
begin
  Result := TrimW(UnicodeString(SysErrorMessage(code)));
end;

function LastErrorText: UnicodeString;
begin
  Result := ErrText(MdGetLastError);
end;

procedure WriteTo(toErr: Boolean; const s: UnicodeString);
var
  h: THandle;
  mode, done: DWORD;
  line: UnicodeString;
  u: UTF8String;
begin
  if toErr then h := MdGetStdHandle(MdStdError) else h := MdGetStdHandle(MdStdOutput);
  line := s + #13#10;
  if MdGetConsoleMode(h, @mode) then
    MdWriteConsoleW(h, PWideChar(line), Length(line), @done, nil)
  else
  begin
    u := UTF8Encode(line);
    if Length(u) > 0 then
      MdWriteFile(h, @u[1], Length(u), @done, nil);
  end;
end;

function LowerW(const s: UnicodeString): UnicodeString;
begin
  Result := s;
  UniqueString(Result);
  if Length(Result) > 0 then
    MdCharLowerBuffW(PWideChar(Result), Length(Result));
end;

function UpperW(const s: UnicodeString): UnicodeString;
begin
  Result := s;
  UniqueString(Result);
  if Length(Result) > 0 then
    MdCharUpperBuffW(PWideChar(Result), Length(Result));
end;

function ValidCodePage(cp: Integer): Boolean;
begin
  Result := (cp > 0) and MdIsValidCodePage(cp);
end;

function EncodeCP(const s: UnicodeString): TBytes;
var
  n: Integer;
  flags: DWORD;
  def: AnsiChar;
  pdef: PAnsiChar;
begin
  SetLength(Result, 0);
  if s = '' then Exit;
  if (CodePage = 65001) or (CodePage >= 50000) then
  begin
    flags := 0;
    pdef := nil;
  end
  else
  begin
    flags := MdNoBestFit;
    def := '?';
    pdef := @def;
  end;
  n := MdWideCharToMultiByte(CodePage, flags, PWideChar(s), Length(s), nil, 0, pdef, nil);
  if n <= 0 then Exit;
  SetLength(Result, n);
  MdWideCharToMultiByte(CodePage, flags, PWideChar(s), Length(s), PAnsiChar(@Result[0]), n, pdef, nil);
end;

function DecodeCP(p: PByte; len: Integer): UnicodeString;
var
  n: Integer;
begin
  Result := '';
  if len <= 0 then Exit;
  n := MdMultiByteToWideChar(CodePage, 0, PAnsiChar(p), len, nil, 0);
  if n <= 0 then Exit;
  SetLength(Result, n);
  MdMultiByteToWideChar(CodePage, 0, PAnsiChar(p), len, PWideChar(Result), n);
end;

function Attrs(const p: UnicodeString): DWORD;
begin
  Result := MdGetFileAttributesW(PWideChar(p));
end;

function PathExists(const p: UnicodeString): Boolean;
begin
  Result := Attrs(p) <> MdInvalidAttr;
end;

function IsDir(const p: UnicodeString): Boolean;
var
  a: DWORD;
begin
  a := Attrs(p);
  Result := (a <> MdInvalidAttr) and ((a and MdAttrDirectory) <> 0);
end;

function IsFile(const p: UnicodeString): Boolean;
var
  a: DWORD;
begin
  a := Attrs(p);
  Result := (a <> MdInvalidAttr) and ((a and MdAttrDirectory) = 0);
end;

function IsLink(const p: UnicodeString): Boolean;
var
  a: DWORD;
begin
  a := Attrs(StripTrailingSeps(p));
  Result := (a <> MdInvalidAttr) and ((a and MdAttrReparse) <> 0);
end;

{ Returns dir\name with the on-disk spelling of name, or '' if no such file. }
function FindFileCI(const dir, name: UnicodeString): UnicodeString;
var
  h: THandle;
  fd: TWin32FindDataW;
begin
  Result := '';
  h := MdFindFirstFileW(PWideChar(JoinPath(dir, name)), @fd);
  if h = THandle(-1) then Exit;
  if (fd.dwFileAttributes and MdAttrDirectory) = 0 then
    Result := JoinPath(dir, UnicodeString(PWideChar(@fd.cFileName[0])));
  MdFindClose(h);
end;

function CallPathApi(kind: Integer; const p: UnicodeString): UnicodeString;
var
  buf: array[0..32767] of WideChar;
  n: DWORD;
begin
  case kind of
    0: n := MdGetFullPathNameW(PWideChar(p), Length(buf), @buf[0], nil);
    1: n := MdGetLongPathNameW(PWideChar(p), @buf[0], Length(buf));
  else
    n := MdGetShortPathNameW(PWideChar(p), @buf[0], Length(buf));
  end;
  if (n > 0) and (n < Length(buf)) then
    Result := UnicodeString(PWideChar(@buf[0]))
  else
    Result := '';
end;

function FullPath(const p: UnicodeString): UnicodeString;
begin
  Result := CallPathApi(0, p);
  if Result = '' then Result := p;
end;

function LongPath(const p: UnicodeString): UnicodeString;
begin
  Result := CallPathApi(1, p);
end;

function ShortPath(const p: UnicodeString): UnicodeString;
begin
  Result := CallPathApi(2, p);
end;

function CurrentDir: UnicodeString;
var
  buf: array[0..32767] of WideChar;
begin
  if MdGetCurrentDirectoryW(Length(buf), @buf[0]) > 0 then
    Result := UnicodeString(PWideChar(@buf[0]))
  else
    Result := '.';
end;

function GetEnvW(const name: UnicodeString): UnicodeString;
var
  buf: array[0..32767] of WideChar;
  n: DWORD;
begin
  n := MdGetEnvironmentVariableW(PWideChar(name), @buf[0], Length(buf));
  if (n > 0) and (n < Length(buf)) then
    Result := UnicodeString(PWideChar(@buf[0]))
  else
    Result := '';
end;

{ Where a path really leads once symlinks are followed, as a plain C:\... or
  \\server\share\... path; '' if it can't be opened. }
function FinalPath(const p: UnicodeString): UnicodeString;
var
  h: THandle;
  buf: array[0..32767] of WideChar;
  n: DWORD;
begin
  Result := '';
  h := MdCreateFileW(PWideChar(p), 0, MdShareRead or MdShareWrite or MdShareDelete, nil,
    MdOpenExisting, MdBackupSemantics, 0);
  if h = THandle(-1) then Exit;
  n := MdGetFinalPathNameByHandleW(h, @buf[0], Length(buf), 0);
  MdCloseHandle(h);
  if (n = 0) or (n >= DWORD(Length(buf))) then Exit;
  Result := UnicodeString(PWideChar(@buf[0]));
  if Copy(Result, 1, 8) = '\\?\UNC\' then
    Result := '\\' + Copy(Result, 9, MaxInt)
  else if Copy(Result, 1, 4) = '\\?\' then
    Result := Copy(Result, 5, MaxInt);
end;

function ReadAllBytes(const p: UnicodeString): TBytes;
var
  h: THandle;
  size, got: DWORD;
begin
  SetLength(Result, 0);
  h := MdCreateFileW(PWideChar(p), MdGenericRead, MdShareRead or MdShareWrite, nil, MdOpenExisting, MdFileAttrNormal, 0);
  if h = THandle(-1) then
    raise EMd.CreateW('cannot read ' + p + ': ' + LastErrorText);
  try
    size := MdGetFileSize(h, nil);
    SetLength(Result, size);
    if size > 0 then
      if not MdReadFile(h, @Result[0], size, @got, nil) or (got <> size) then
        raise EMd.CreateW('cannot read ' + p + ': ' + LastErrorText);
  finally
    MdCloseHandle(h);
  end;
end;

procedure WriteAllBytes(const p: UnicodeString; const data: TBytes);
var
  h: THandle;
  done: DWORD;
  ok: Boolean;
begin
  h := MdCreateFileW(PWideChar(p), MdGenericWrite, 0, nil, MdCreateAlways, MdFileAttrNormal, 0);
  if h = THandle(-1) then
    raise EMd.CreateW(p + ': ' + LastErrorText);
  ok := True;
  if Length(data) > 0 then
    ok := MdWriteFile(h, @data[0], Length(data), @done, nil) and (done = DWORD(Length(data)));
  ok := ok and MdFlushFileBuffers(h);
  if not ok then
  begin
    MdCloseHandle(h);
    raise EMd.CreateW(p + ': ' + LastErrorText);
  end;
  MdCloseHandle(h);
end;

procedure CopyMode(const src, dst: UnicodeString);
begin
end;

function RenameReplace(const src, dst: UnicodeString): Boolean;
begin
  Result := MdMoveFileExW(PWideChar(src), PWideChar(dst), MdMoveReplace or MdMoveWriteThrough);
end;

procedure RemoveFileW(const p: UnicodeString);
begin
  MdDeleteFileW(PWideChar(p));
end;

function CopyFileTo(const src, dst: UnicodeString): Boolean;
begin
  Result := MdCopyFileW(PWideChar(src), PWideChar(dst), False);
end;

function MakeDir(const p: UnicodeString): Boolean;
begin
  Result := MdCreateDirectoryW(PWideChar(p), nil);
end;

function MakeDirLink(const link, target: UnicodeString; out err: UnicodeString): Boolean;
var
  code: DWORD;
begin
  err := '';
  Result := MdCreateSymbolicLinkW(PWideChar(link), PWideChar(target), MdSymlinkDirectory or MdSymlinkUnprivileged);
  if Result then Exit;
  code := MdGetLastError;
  if code = MdErrorInvalidParameter then
  begin
    Result := MdCreateSymbolicLinkW(PWideChar(link), PWideChar(target), MdSymlinkDirectory);
    if Result then Exit;
    code := MdGetLastError;
  end;
  err := ErrText(code);
  if code = MdErrorPrivilegeNotHeld then
    err := err + '. Run filedirs as administrator or turn on Windows Developer Mode.';
end;

procedure RemoveLink(const p: UnicodeString);
begin
  MdRemoveDirectoryW(PWideChar(p));
end;

{ Subdirectories and files directly inside dir. Symlinked directories are only
  listed when follow is set. }
function ListDir(const dir: UnicodeString; follow: Boolean; out subs, files: TUStrArray): Boolean;
var
  h: THandle;
  fd: TWin32FindDataW;
  name: UnicodeString;
begin
  SetLength(subs, 0);
  SetLength(files, 0);
  h := MdFindFirstFileW(PWideChar(JoinPath(dir, '*')), @fd);
  if h = THandle(-1) then Exit(False);
  repeat
    name := UnicodeString(PWideChar(@fd.cFileName[0]));
    if (fd.dwFileAttributes and MdAttrDirectory) <> 0 then
    begin
      if (name <> '.') and (name <> '..')
         and (follow or ((fd.dwFileAttributes and MdAttrReparse) = 0)) then
        AddStr(subs, name);
    end
    else
      AddStr(files, name);
  until not MdFindNextFileW(h, @fd);
  MdFindClose(h);
  Result := True;
end;

function GetArgs: TUStrArray;
var
  argv: PPWideChar;
  argc, i: LongInt;
begin
  SetLength(Result, 0);
  argv := MdCommandLineToArgvW(MdGetCommandLineW, @argc);
  if argv = nil then Exit;
  for i := 1 to argc - 1 do
    AddStr(Result, UnicodeString(argv[i]));
  MdLocalFree(argv);
end;
