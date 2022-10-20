unit PingTRD;

{$mode objfpc}{$H+}

interface

uses
  Classes, Forms, Controls, SysUtils, Process, Graphics;

type
  CheckPing = class(TThread)
  private

    { Private declarations }
  protected
  var
    PingStr: TStringList;

    procedure Execute; override;
    procedure ShowStatus;

  end;

implementation

uses unit1;

{ TRD }

procedure CheckPing.Execute;
var
  PingProcess: TProcess;
begin
  try
    FreeOnTerminate := True; //Уничтожать по завершении
    PingStr := TStringList.Create;

    PingProcess := TProcess.Create(nil);
    PingProcess.Executable := 'bash';

    while not Terminated do
    begin
      PingProcess.Parameters.Clear;
      PingProcess.Parameters.Add('-c');
      PingProcess.Parameters.Add(
        // 'ping -c 2 google.com &> /dev/null && [[ $(ip -br a | grep wg[[:digit:]]) ]] && echo "yes" || echo "no"');
        '[[ $(fping google.com) && $(ip -br a | grep ppp0) ]] && echo "yes" || echo "no"');

      PingProcess.Options := [poUsePipes, poWaitOnExit];

      PingProcess.Execute;
      PingStr.LoadFromStream(PingProcess.Output);
      Synchronize(@ShowStatus);

      Sleep(500);
    end;

  finally
    PingStr.Free;
    PingProcess.Free;
    Terminate;
  end;
end;

//Индикация - светодиод
procedure CheckPing.ShowStatus;
begin
  with MainForm do
  begin
    if Trim(PingStr[0]) = 'yes' then
    begin
      Shape1.Brush.Color := clLime;
      StartBtn.Enabled := False;
      RouterEdit.Enabled := False;
      LogMemo.Append('SSTP VPN запущена: ' + DateToStr(Now));
    end
    else
    begin
      Shape1.Brush.Color := clYellow;
      StartBtn.Enabled := True;
      RouterEdit.Enabled := True;
      LogMemo.Append('SSTP VPN остановлен: ' + DateToStr(Now));
    end;

    Shape1.Repaint;
    StartBtn.Refresh;
  end;
end;

end.
