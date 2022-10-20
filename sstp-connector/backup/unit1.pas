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
    UserEdit: TEdit;
    PasswordEdit: TEdit;
    ServerEdit: TEdit;
    RouterEdit: TEdit;
    IniPropStorage1: TIniPropStorage;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    LogMemo: TMemo;
    Shape1: TShape;
    StartBtn: TSpeedButton;
    StopBtn: TSpeedButton;
    StaticText1: TStaticText;
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
  if FileExists(GetUserDir + '.config/sstp-connector/clear') then
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
  if not DirectoryExists(GetUserDir + '.config') then MkDir('/root/.config');
  if not DirectoryExists(GetUserDir + '.config/sstp-connector') then
    MkDir(GetUserDir + '.config/sstp-connector');

  IniPropStorage1.IniFileName := GetUserDir + '.config/sstp-connector/settings.conf';

  //Поток проверки пинга
  FCheckPingThread := CheckPing.Create(False);
  FCheckPingThread.Priority := tpNormal;
end;

procedure TMainForm.ClearBoxChange(Sender: TObject);
var
  S: ansistring;
begin
  if not ClearBox.Checked then
    RunCommand('/bin/bash', ['-c', 'rm -f ~/.config/sstp-connector/clear'], S)
  else
    RunCommand('/bin/bash', ['-c', 'touch ~/.config/sstp-connector/clear'], S);
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  IniPropStorage1.Restore;

  AutostartBox.Checked := CheckAutoStart;
  ClearBox.Checked := CheckClear;
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
    S.Add('killall sstpc 2>/dev/null; ip route del default; ip route add default via ' +
      RouterEdit.Text);
    S.Add('"' + ExtractFileDir(Application.ExeName) + '/update-resolv-conf" down');

    //Проверка пинга Router IP
    S.Add('[[ $(fping ' + RouterEdit.Text + ') ]] || exit 1');

    //Подключаемся к серверу
    S.Add('sstpc --save-server-route --tls-ext --cert-warn --user ' +
      UserEdit.Text + ' --password ' + PasswordEdit.Text + ' ' +
      ServerEdit.Text + ' noauth &');

    //Ожидание получения ppp0 = ip_address от сервера
    S.Add('count=1');
    S.Add('while [[ -z $(ip a show ppp0 2>/dev/null | grep inet) ]]; do');

    S.Add('echo "' + SConnectGetIP + '" $count');
    S.Add('sleep 1');
    S.Add('count=$(( $count + 1 ))');
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

    S.SaveToFile(GetUserDir + '.config/sstp-connector/connect.sh');

    FStartConnect := StartConnect.Create(False);
    FStartConnect.Priority := tpNormal;
  finally
    S.Free;
  end;
end;

//Down ppp0  (pkill -f /root/.config/sstp-connector/connect.sh)
procedure TMainForm.StopBtnClick(Sender: TObject);
begin
  //Проверка IP роутера иначе будут возвращены неправильные настройки
  IPRouterCheck;

  LogMemo.Text := SStopVPN;

  StartProcess('killall sstpc; ip route del default; ip route add default via ' +
    RouterEdit.Text + '; "' + ExtractFileDir(Application.ExeName) +
    '/update-resolv-conf" down; ' + 'pkill -f /root/.config/sstp-connector/connect.sh');

  Shape1.Brush.Color := clYellow;
  Shape1.Repaint;
end;

end.
