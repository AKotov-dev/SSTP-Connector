unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Buttons,
  ComCtrls, ExtCtrls, IniPropStorage, Process, DefaultTranslator;

type

  { TMainForm }

  TMainForm = class(TForm)
    DefRouteBox: TCheckBox;
    ClearBox: TCheckBox;
    AutoStartBox: TCheckBox;
    UserEdit: TEdit;
    PasswordEdit: TEdit;
    ServerEdit: TEdit;
    IniPropStorage1: TIniPropStorage;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
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

  private

  public

  end;

//Ресурсы перевода
resourcestring
  SConnectYes = 'The connection is established:';
  SDefaultGW = 'Default route:';
  SStopVPN = 'VPN is stopped. Switching to a local network...';
  SDNS = 'Active DNS:';

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
end;

{Запуск скрипта; чтобы менять DefaultRoute автоматически,
добавить в /etc/ppp/options - defaultroute и replacedefaultroute,
а при запуске sstpc --save-server-route
https://unix.stackexchange.com/questions/448169/pppd-default-route-configuration
http://manpages.ylsoftware.com/ru/pppd.8.html}
procedure TMainForm.StartBtnClick(Sender: TObject);
var
  S: TStringList;
  DefRoute: string;
  FStartConnect: TThread;
begin
  //Проверка на пустоту
  if (Trim(UserEdit.Text) = '') or (Trim(PasswordEdit.Text) = '') or
    (Trim(ServerEdit.Text) = '') then Exit;

  //ppp0 - маршрут по умолчанию?
  if DefRouteBox.Checked then DefRoute := 'defaultroute replacedefaultroute'
  else
    DefRoute := '';

  try
    S := TStringList.Create;

    S.Add('#!/bin/bash');
    S.Add('');

    //Содаём пускач для systemd (Type=simple)
    S.Add('sstpc --save-server-route --tls-ext --cert-warn --user ' +
      UserEdit.Text + ' --password ' + PasswordEdit.Text + ' ' +
      ServerEdit.Text + ' noauth ' + DefRoute);

    //Если VPN глобальный - заменить DNS
    if DefRouteBox.Checked then
      S.Add('/etc/sstp-connector/update-resolv-conf up');
    S.Add('');
    S.Add('exit 0');

    S.SaveToFile('/etc/sstp-connector/connect-systemd.sh');
    StartProcess('chmod +x /etc/sstp-connector/connect-systemd.sh');

    //Создаём пускач для запуска через GUI
    S.Clear;

    S.Add('#!/bin/bash');
    S.Add('');

    //Подключаемся к серверу (от --log-level зависим выход из потока, min=2)
    S.Add('sstpc --log-level 3 --log-stdout --save-server-route --tls-ext --cert-warn --user '
      + UserEdit.Text + ' --password ' + PasswordEdit.Text + ' ' +
      ServerEdit.Text + ' noauth ' + DefRoute + '&');

    //Ожидание получения ppp0 = ip_address от сервера
    S.Add('count=0');
    S.Add('while [[ -z $(ip a show ppp0 2>/dev/null | grep inet) ]]; do');

    S.Add('sleep 1');
    S.Add('count=$(( $count + 1 ))');
    S.Add('done');

    S.Add('echo -e "\n' + SConnectYes + '\n---"');
    S.Add('ip a show ppp0');

    S.Add('echo -e "\n' + SDefaultGW + '\n---"');

    //Если VPN глобальный - заменить DNS
    if DefRouteBox.Checked then
    begin
      S.Add('/etc/sstp-connector/update-resolv-conf up');
      S.Add('ip route | grep ppp0');
    end
    else
      S.Add('ip route | grep default');

    //Вывод DNS
    S.Add('echo -e "\n' + SDNS + '\n---"');
    S.Add('grep "nameserver" /etc/resolv.conf');

    S.Add('');
    S.Add('exit 0');

    S.SaveToFile('/etc/sstp-connector/connect.sh');

    //Запускаем скрипт
    FStartConnect := StartConnect.Create(False);
    FStartConnect.Priority := tpNormal;

  finally
    S.Free;
  end;
end;

//Down ppp0
procedure TMainForm.StopBtnClick(Sender: TObject);
begin
  LogMemo.Text := SStopVPN;

  StartBtn.Enabled := True;
  Shape1.Brush.Color := clYellow;

  StartProcess('/etc/sstp-connector/stop-connect.sh');
end;

end.
