unit start_trd;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process;

type
  TStartConnect = class(TThread)
  private
    FProcess: TProcess;
    FBuffer: string;
    FNewLines: TStringList;

    procedure DoStartUI;
    procedure DoStopUI;
    procedure DoShowLog;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses Unit1;

  { TStartConnect }

constructor TStartConnect.Create;
begin
  inherited Create(True); // suspended
  FreeOnTerminate := False;

  FNewLines := TStringList.Create;
end;

destructor TStartConnect.Destroy;
begin
  FNewLines.Free;
  inherited Destroy;
end;

procedure TStartConnect.Execute;
var
  Buffer: array[0..2047] of byte;
  ReadCount: longint;
  S, Line: string;
  P: integer;
begin
  Queue(@DoStartUI);

  FProcess := TProcess.Create(nil);
  try
    FProcess.Executable := 'bash';
    FProcess.Parameters.Add('-c');
    FProcess.Parameters.Add(
      'chmod +x /etc/sstp-connector/connect.sh; ' +
      '/etc/sstp-connector/connect.sh');

    FProcess.Options := [poUsePipes, poStderrToOutPut];
    FProcess.Execute;

    while (not Terminated) and (FProcess.Running or
        (FProcess.Output.NumBytesAvailable > 0)) do
    begin
      if FProcess.Output.NumBytesAvailable > 0 then
      begin
        ReadCount := FProcess.Output.Read(Buffer, SizeOf(Buffer));
        SetString(S, PChar(@Buffer[0]), ReadCount);

        FBuffer := FBuffer + S;

        // разбор строк
        while True do
        begin
          P := Pos(LineEnding, FBuffer);
          if P = 0 then Break;

          Line := Copy(FBuffer, 1, P - 1);
          Delete(FBuffer, 1, P + Length(LineEnding) - 1);

          FNewLines.Add(Line);
        end;

        if FNewLines.Count > 0 then
          Queue(@DoShowLog);
      end
      else
        Sleep(50);
    end;

  finally
    FProcess.Free;
    Queue(@DoStopUI);
  end;
end;

{ ==== Вывод лога ==== }

// Старт выполения
procedure TStartConnect.DoStartUI;
begin
  with MainForm do
  begin
    LogMemo.Clear;
    StartBtn.Enabled := False;
    StartBtn.Repaint;
  end;
end;

// Стоп выполнения
procedure TStartConnect.DoStopUI;
begin
  with MainForm do
  begin
    StartBtn.Enabled := True;
    StartBtn.Repaint;
    IniPropStorage1.Save;
  end;
end;

// Показываем лог
procedure TStartConnect.DoShowLog;
var
  i: integer;
begin
  for i := 0 to FNewLines.Count - 1 do
    MainForm.LogMemo.Lines.Add(FNewLines[i]);

  FNewLines.Clear;

  MainForm.LogMemo.SelStart := Length(MainForm.LogMemo.Text);
  MainForm.LogMemo.SelLength := 0;
end;

end.
