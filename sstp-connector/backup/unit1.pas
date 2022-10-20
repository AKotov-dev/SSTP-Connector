unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Buttons,
  ComCtrls, ExtCtrls, IniPropStorage, Process, DefaultTranslator;

type

  { TMainForm }

  TMainForm = class(TForm)
    ClearBox: TCheckBox;
    AutoStartBox: TCheckBox;
    ProgressBar1: TProgressBar;
    UserEdit: TEdit;
    PasswordEdit: TEdit;
    ServerEdit: TEdit;
    RouterEdit: TEdit;
    IniPropStorage1: TIniPropStorage;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    LogMemo: TMemo;
    Shape1: TShape;
    StartBtn: TSpeedButton;
    StopBtn: TSpeedButton;
    StaticText1: TStaticText;
    procedure AutoStartBoxChange(Sender: TObject);
    procedure ClearBoxChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure StartBtnClick(Sender: TObject);
    procedure StopBtnClick(Sender: TObject);
    procedure StartProcess(command: string);
    procedure IPRouterCheck;
  private

  public

  end;

//Ресурсы перевода
resourcestring
  SConnectGetIP = 'Connection/Getting an IP (ppp0), wait...';
  SConnectYes = 'The connection is established:';
  SDefaultGW = 'Default route changed:';
  SStopVPN = 'VPN is stopped. Switching to a local network...';
  SCheckRouterIP = 'Checking the router' + '''' + 's IP...';
  SInValidRouterIP = 'Invalid router IP is specified!';

var
  MainForm: TMainForm;

implementation

uses start_trd, pingtrd;

{$R *.lfm}

{ TMainForm }

//Общая процедура запуска команд (асинхронная)
procedure TMainForm.StartProcess(command: string);
var
  ExProcess: TProcess;
begin
  Application.ProcessMessages;
  ExProcess := TProcess.Create(nil);
  try
    ExProcess.Executable := '/bin/bash';
    ExProcess.Parameters.Add('-c');
    ExProcess.Parameters.Add(command);
    //  ExProcess.Options := ExProcess.Options + [poWaitOnExit];
    ExProcess.Execute;
  finally
    ExProcess.Free;
  end;
end;

//Проверка IP роутера
procedure TMainForm.IPRouterCheck;
var
  GWPing: ansistring;
begin
  //Проверка на пустоту
  if (Trim(UserEdit.Text) = '') or (Trim(PasswordEdit.Text) = '') or
    (Trim(ServerEdit.Text) = '') or (Trim(RouterEdit.Text) = '') then Abort;

  Screen.Cursor := crHourGlass;
  LogMemo.Text := SCheckRouterIP;
  Application.ProcessMessages;
  if RunCommand('/bin/bash', ['-c', 'fping ' + RouterEdit.Text +
    ' &> /dev/null && echo "yes" || echo "no"'], GWPing) then
    if Trim(GWPing) <> 'yes' then
    begin
      LogMemo.Text := SInValidRouterIP;
      Screen.Cursor := crDefault;
      Abort;
    end;
  Screen.Cursor := crDefault;
end;

//Проверка чекбокса ClearBox (очистка кеш/cookies)
function CheckClear: boolean;
begin
  if FileExists('/etc/sstp-connector/clear') then
    Result := True
  else
    Result := False;
end;

//Проверка чекбокса AutoStart
function CheckAutoStart: boolean;
var
  S: ansistring;
begin
  RunCommand('/bin/bash', ['-c',
    '[[ -n $(systemctl is-enabled sstp-connector | grep "enabled") ]] && echo "yes"'],
    S);

  if Trim(S) = 'yes' then
    Result := True
  else
    Result := False;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  FCheckPingThread: TThread;
begin
  MainForm.Caption := Application.Title;

  //Создаём рабочую директорию
  if not DirectoryExists('/etc/sstp-connector') then MkDir('/etc/sstp-connector');

  IniPropStorage1.IniFileName := '/etc/sstp-connector/settings.conf';

  //Поток проверки пинга
  FCheckPingThread := CheckPing.Create(False);
  FCheckPingThread.Priority := tpNormal;
end;

procedure TMainForm.ClearBoxChange(Sender: TObject);
var
  S: ansistring;
begin
  if not ClearBox.Checked then
    RunCommand('/bin/bash', ['-c', 'rm -f /etc/sstp-connector/clear'], S)
  else
    RunCommand('/bin/bash', ['-c', 'touch /etc/sstp-connector/clear'], S);
end;

procedure TMainForm.AutoStartBoxChange(Sender: TObject);
var
  S: ansistring;
begin
  Screen.Cursor := crHourGlass;
  Application.ProcessMessages;

  if not AutoStartBox.Checked then
    RunCommand('/bin/bash', ['-c', 'systemctl disable sstp-connector.service'], S)
  else
    RunCommand('/bin/bash', ['-c', 'systemctl enable sstp-connector.service'], S);
  Screen.Cursor := crDefault;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  IniPropStorage1.Restore;

  AutostartBox.Checked := CheckAutoStart;
  ClearBox.Checked := CheckClear;

  //Статус при новом открытии GUI
  // if Shape1.Brush.Color=clLime then LogMemo.Text:= SConnectYes;
end;

procedure TMainForm.StartBtnClick(Sender: TObject);
var
  S: TStringList;
  FStartConnect: TThread;
begin
  //Проверка IP роутера иначе будут установлены неправильные настройки
  IPRouterCheck;

  try
    S := TStringList.Create;

    S.Add('#!/bin/bash');
    S.Add('');

    //Восстанавливаем дефолтный шлюз и DNS
    S.Add('pkill sstpc; ip route del default; ip route add default via ' +
      RouterEdit.Text);
    S.Add('"' + ExtractFileDir(Application.ExeName) + '/update-resolv-conf" down');

    //Подключаемся к серверу (от --log-level зависим выход из потока, min=2)
    S.Add('sstpc --log-level 3 --log-stdout --save-server-route --tls-ext --cert-warn --user '
      + UserEdit.Text + ' --password ' + PasswordEdit.Text + ' ' +
      ServerEdit.Text + ' noauth &');

    //Ожидание получения ppp0 = ip_address от сервера
    S.Add('count=0');
    S.Add('while [[ -z $(ip a show ppp0 2>/dev/null | grep inet) ]]; do');

    //S.Add('echo "' + SConnectGetIP + '" $count');
    S.Add('sleep 1');
    S.Add('count=$(( $count + 1 ))');
    S.Add('[[ $count == 2 ]] && exit 1');
    S.Add('done');

    S.Add('echo -e "\n' + SConnectYes + '\n---"');
    S.Add('ip a show ppp0');

    //Адрес получен, заменить DNS и DEFAULT_GATEWAY
    S.Add('"' + ExtractFileDir(Application.ExeName) + '/update-resolv-conf" up');

    S.Add('ip route del default; ip route add default dev ppp0');
    S.Add('echo -e "\n' + SDefaultGW + '\n---"');
    S.Add('ip route | grep ppp0');

    S.Add('');
    S.Add('exit 0;');

    S.SaveToFile('/etc/sstp-connector/connect.sh');

    FStartConnect := StartConnect.Create(False);
    FStartConnect.Priority := tpNormal;

    //Файл останова VPN (возврат Default-GW и DNS) для systemd
    S.Clear;

    S.Add('#!/bin/bash');
    S.Add('');
    S.Add('pkill sstpc; ip route del default; ip route add default via ' +
      RouterEdit.Text);
    S.Add('"' + ExtractFileDir(Application.ExeName) + '/update-resolv-conf" down');
    S.Add('pkill -f /etc/sstp-connector/connect.sh');
    S.Add('');
    S.Add('exit 0');

    S.SaveToFile('/etc/sstp-connector/stop-connect.sh');

    StartProcess('chmod +x /etc/sstp-connector/stop-connect.sh');
  finally
    S.Free;
  end;
end;

//Down ppp0  (pkill -f /etc/sstp-connector/connect.sh)
procedure TMainForm.StopBtnClick(Sender: TObject);
begin
  //Проверка IP роутера иначе будут возвращены неправильные настройки
  IPRouterCheck;

  LogMemo.Text := SStopVPN;

  if FileExists('/etc/sstp-connector/stop-connect.sh') then
    StartProcess('/etc/sstp-connector/stop-connect.sh');

  Shape1.Brush.Color := clYellow;
  Shape1.Repaint;
end;

end.
