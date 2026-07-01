// EDP Eiffert Systems – RunProgramm Logger
//
// EDP-Konfiguration:
//   Programm  : C:\ProgramData\EDPLogger\edp_logger.exe
//   Parameter : "<%EINSATZNUMMER%>|<%SONDERSIGNAL%>|<%STICHWORT%>|<%STICHWORT_KLARTEXT%>|<%MELDUNG%>|<%OBJEKTNAME%>|<%STRASSE%>|<%HAUSNUMMER%>|<%ORT%>|<%EINSATZMITTEL%>"
//                ^^^ äußere Anführungszeichen sind PFLICHT damit Leerzeichen in Feldern nicht splitten
//
// Alarmierungs-Konfiguration (edp_logger.ini):
//   edp_api_url = https://api.example.org  ← EDP-API-Server (ohne /api/v1)
//   edp_user    = dispatcher               ← Benutzer mit Rolle User/Admin
//   edp_pass    = <passwort>               ← Passwort des Benutzers
//
// Bei gesetzter edp_api_url meldet sich edp_logger beim Einsatz an der EDP-API
// an (POST /api/v1/auth/login) und löst eine Alarmierung aus
// (POST /api/v1/alarmierung) für das Gerät mit der passenden ISSI.
// Die TruppApp pollt /api/v1/alarmierung und alarmiert das Gerät sofort.

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"gopkg.in/ini.v1"
)

// 10 Felder, pipe-getrennt
var fieldNames = []string{
	"EINSATZNUMMER",      //  1
	"SONDERSIGNAL",       //  2
	"STICHWORT",          //  3
	"STICHWORT_KLARTEXT", //  4
	"MELDUNG",            //  5
	"OBJEKTNAME",         //  6
	"STRASSE",            //  7
	"HAUSNUMMER",         //  8
	"ORT",                //  9
	"EINSATZMITTEL",      // 10
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

type Config struct {
	LogDir    string
	LogPrefix string
	DateFmt   string
	TimeFmt   string
	Separator string
	Rotate    string
	Console   bool
	EDPValue  bool
	EDPApiURL string // EDP-API-Server, z.B. "https://api.example.org" (ohne /api/v1)
	EDPUser   string // Benutzer mit Rolle User/Admin für die Alarmierung
	EDPPass   string // Passwort des Benutzers
}

func programDataDir() string {
	if v := os.Getenv("ProgramData"); v != "" {
		return v
	}
	return `C:\ProgramData`
}

func exeDir() string {
	exe, err := os.Executable()
	if err != nil {
		return programDataDir()
	}
	if real, err := filepath.EvalSymlinks(exe); err == nil {
		exe = real
	}
	return filepath.Dir(exe)
}

func defaultConfig() *Config {
	return &Config{
		LogDir:    filepath.Join(programDataDir(), "EDPLogger", "logs"),
		LogPrefix: "einsatz",
		DateFmt:   "2006-01-02",
		TimeFmt:   "15:04:05",
		Separator: " | ",
		Rotate:    "daily",
		Console:   false,
		EDPValue:  false,
		EDPApiURL: "",
		EDPUser:   "",
		EDPPass:   "",
	}
}

func loadConfig() *Config {
	cfg := defaultConfig()
	candidates := []string{
		filepath.Join(exeDir(), "edp_logger.ini"),
		filepath.Join(programDataDir(), "EDPLogger", "edp_logger.ini"),
	}
	var cfgPath string
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			cfgPath = p
			break
		}
	}
	if cfgPath == "" {
		d := filepath.Join(programDataDir(), "EDPLogger")
		_ = os.MkdirAll(d, 0755)
		writeDefaultIni(filepath.Join(d, "edp_logger.ini"))
		return cfg
	}
	f, err := ini.Load(cfgPath)
	if err != nil {
		return cfg
	}
	sec := f.Section("")
	if v := sec.Key("log_dir").String(); v != "" {
		cfg.LogDir = v
	}
	if v := sec.Key("log_prefix").String(); v != "" {
		cfg.LogPrefix = v
	}
	if v := sec.Key("date_format").String(); v != "" {
		cfg.DateFmt = v
	}
	if v := sec.Key("time_format").String(); v != "" {
		cfg.TimeFmt = v
	}
	if v := sec.Key("separator").String(); v != "" {
		cfg.Separator = v
	}
	if v := sec.Key("rotate").String(); v != "" {
		cfg.Rotate = strings.ToLower(v)
	}
	cfg.Console = strings.ToLower(sec.Key("console").String()) == "true"
	cfg.EDPValue = strings.ToLower(sec.Key("edp_value").String()) == "true"
	if v := sec.Key("edp_api_url").String(); v != "" {
		cfg.EDPApiURL = strings.TrimRight(v, "/")
	}
	if v := sec.Key("edp_user").String(); v != "" {
		cfg.EDPUser = v
	}
	if v := sec.Key("edp_pass").String(); v != "" {
		cfg.EDPPass = v
	}
	return cfg
}

func writeDefaultIni(path string) {
	_ = os.WriteFile(path, []byte(
		"; EDP Logger – Konfiguration\n"+
			"; C:\\ProgramData\\EDPLogger\\edp_logger.ini\n\n"+
			"[DEFAULT]\n"+
			"log_dir      = C:\\ProgramData\\EDPLogger\\logs\n"+
			"log_prefix   = einsatz\n"+
			"date_format  = 2006-01-02\n"+
			"time_format  = 15:04:05\n"+
			"separator    =  | \n"+
			"rotate       = daily\n"+
			"console      = false\n"+
			"; true wenn EDP 'Wert' als ersten Parameter voranstellt\n"+
			"edp_value    = false\n\n"+
			"; --- TruppApp Alarmierung via EDP-API ---\n"+
			"; EDP-API-Server-URL (ohne abschließenden Slash, ohne /api/v1)\n"+
			"; edp_api_url = https://api.example.org\n"+
			"; Benutzer mit Rolle User/Admin und zugehöriges Passwort\n"+
			"; edp_user    = dispatcher\n"+
			"; edp_pass    = dein-passwort\n",
	), 0644)
}

// ---------------------------------------------------------------------------
// Logging-Helpers
// ---------------------------------------------------------------------------

func openAppend(path string) (*os.File, error) {
	return os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
}

// writeDiagnostic – immer als Erstes; zeigt ob EDP das Programm überhaupt startet
func writeDiagnostic(args []string) {
	d := filepath.Join(programDataDir(), "EDPLogger")
	_ = os.MkdirAll(d, 0755)
	f, err := openAppend(filepath.Join(d, "startup.log"))
	if err != nil {
		return
	}
	defer f.Close()
	exe, _ := os.Executable()
	wd, _ := os.Getwd()
	fmt.Fprintf(f, "[%s] STARTUP\n  EXE : %s\n  CWD : %s\n  ARGC: %d\n",
		time.Now().Format("2006-01-02 15:04:05"), exe, wd, len(args))
	for i, a := range args {
		fmt.Fprintf(f, "  [%02d] %q\n", i, a)
	}
	fmt.Fprintln(f)
}

func writeFallback(origPath string, writeErr error, entry string) {
	fb := filepath.Join(programDataDir(), "EDPLogger", "fallback.log")
	f, err := openAppend(fb)
	if err != nil {
		return
	}
	defer f.Close()
	fmt.Fprintf(f, "[%s] FEHLER: %s → %v\n  %s\n",
		time.Now().Format("2006-01-02 15:04:05"), origPath, writeErr, entry)
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

func cleanValue(s string) string {
	s = strings.ReplaceAll(s, "\r\n", " / ")
	s = strings.ReplaceAll(s, "\r", " ")
	s = strings.ReplaceAll(s, "\n", " / ")
	return strings.TrimSpace(s)
}

func parseFields(raw string) map[string]string {
	parts := strings.Split(raw, "|")
	fields := make(map[string]string, len(fieldNames))
	for i, name := range fieldNames {
		if i < len(parts) {
			fields[name] = cleanValue(parts[i])
		} else {
			fields[name] = ""
		}
	}
	return fields
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

// cleanSignal entfernt das EDP-Präfix "0=" / "1=" aus dem Sondersignal-Feld.
func cleanSignal(s string) string {
	return regexp.MustCompile(`^\d+=`).ReplaceAllString(s, "")
}

// cleanMittel extrahiert aus dem EDP-Einsatzmittel-Block nur die reinen Fahrzeug-Rufnamen.
func cleanMittel(s string) string {
	dateRe := regexp.MustCompile(`\d{2}\.\d{2}\.\d{4}`)
	timeRe := regexp.MustCompile(`\d{2}:\d{2}:\d{2}`)
	dashRe := regexp.MustCompile(`--:--`)
	countRe := regexp.MustCompile(`\d+/\d+/\d+\s*=\s*\d+`)
	spaceRe := regexp.MustCompile(`\s+`)

	var names []string
	for _, part := range strings.Split(s, " / ") {
		clean := dateRe.ReplaceAllString(part, "")
		clean = timeRe.ReplaceAllString(clean, "")
		clean = dashRe.ReplaceAllString(clean, "")
		clean = countRe.ReplaceAllString(clean, "")
		clean = spaceRe.ReplaceAllString(clean, " ")
		clean = strings.Trim(clean, " /")
		if clean != "" {
			names = append(names, clean)
		}
	}
	return strings.Join(names, " / ")
}

func g(m map[string]string, k string) string { return m[k] }

func formatEntry(fields map[string]string, cfg *Config, vehicleID string) string {
	now := time.Now()
	sep := cfg.Separator
	adresse := cleanValue(g(fields, "STRASSE") + " " + g(fields, "HAUSNUMMER"))
	parts := []string{
		fmt.Sprintf("[%s %s]", now.Format(cfg.DateFmt), now.Format(cfg.TimeFmt)),
		"ENR=" + g(fields, "EINSATZNUMMER"),
	}
	if vehicleID != "" {
		parts = append(parts, "FAHRZEUG="+vehicleID)
	}
	parts = append(parts,
		"SIGNAL="+cleanSignal(g(fields, "SONDERSIGNAL")),
		"STICHW="+g(fields, "STICHWORT"),
		"KLARTEXT="+g(fields, "STICHWORT_KLARTEXT"),
		"MELDUNG="+g(fields, "MELDUNG"),
		"OBJEKT="+g(fields, "OBJEKTNAME"),
		"ADRESSE="+adresse,
		"ORT="+g(fields, "ORT"),
		"MITTEL="+cleanMittel(g(fields, "EINSATZMITTEL")),
	)
	return strings.Join(parts, sep)
}

func logPath(cfg *Config) string {
	if err := os.MkdirAll(cfg.LogDir, 0755); err != nil {
		cfg.LogDir = filepath.Join(programDataDir(), "EDPLogger", "logs")
		_ = os.MkdirAll(cfg.LogDir, 0755)
	}
	var name string
	if cfg.Rotate == "daily" {
		name = fmt.Sprintf("%s_%s.log", cfg.LogPrefix, time.Now().Format("2006-01-02"))
	} else {
		name = cfg.LogPrefix + ".log"
	}
	return filepath.Join(cfg.LogDir, name)
}

func writeLog(path, entry string) error {
	f, err := openAppend(path)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = fmt.Fprintln(f, entry)
	return err
}

// ---------------------------------------------------------------------------
// EDP-API Alarmierung
// ---------------------------------------------------------------------------

// alarmRequest ist das JSON-Payload für POST /api/v1/alarmierung.
// Entspricht dem AlarmRequest-Modell der EDP-API. Der Zeitstempel (ts) wird
// serverseitig gesetzt.
type alarmRequest struct {
	Issis     []string `json:"issis"`
	ENR       string   `json:"enr"`
	Signal    string   `json:"signal"`
	Stichwort string   `json:"stichwort"`
	Klartext  string   `json:"klartext"`
	Meldung   string   `json:"meldung"`
	Objekt    string   `json:"objekt"`
	Strasse   string   `json:"strasse"`
	HNR       string   `json:"hnr"`
	Ort       string   `json:"ort"`
	Mittel    string   `json:"mittel"`
}

// logAlarmError protokolliert einen Alarmierungsfehler in startup.log,
// blockiert aber den Ablauf nicht.
func logAlarmError(format string, a ...any) {
	d := filepath.Join(programDataDir(), "EDPLogger")
	if f, ferr := openAppend(filepath.Join(d, "startup.log")); ferr == nil {
		fmt.Fprintf(f, "[%s] EDP-API-ALARM-FEHLER: ", time.Now().Format("2006-01-02 15:04:05"))
		fmt.Fprintf(f, format+"\n", a...)
		f.Close()
	}
}

// login meldet sich an der EDP-API an und gibt den Access-Token zurück.
func login(cfg *Config, client *http.Client) (string, error) {
	body, _ := json.Marshal(map[string]string{
		"username": cfg.EDPUser,
		"password": cfg.EDPPass,
	})
	req, err := http.NewRequest(http.MethodPost,
		cfg.EDPApiURL+"/api/v1/auth/login", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("login HTTP %d", resp.StatusCode)
	}
	var parsed struct {
		Data struct {
			AccessToken string `json:"accessToken"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return "", err
	}
	if parsed.Data.AccessToken == "" {
		return "", fmt.Errorf("kein accessToken in Antwort")
	}
	return parsed.Data.AccessToken, nil
}

// sendAlarm meldet sich an der EDP-API an und löst eine Alarmierung für das
// Gerät mit der angegebenen ISSI (vehicleID) aus. Die TruppApp empfängt sie
// per Polling. Fehler werden in startup.log protokolliert, blockieren aber
// den Ablauf nicht.
func sendAlarm(fields map[string]string, vehicleID string, cfg *Config) {
	if cfg.EDPApiURL == "" || vehicleID == "" {
		return
	}

	client := &http.Client{Timeout: 10 * time.Second}

	token, err := login(cfg, client)
	if err != nil {
		logAlarmError("%v", err)
		return
	}

	payload := alarmRequest{
		Issis:     []string{vehicleID},
		ENR:       g(fields, "EINSATZNUMMER"),
		Signal:    cleanSignal(g(fields, "SONDERSIGNAL")),
		Stichwort: g(fields, "STICHWORT"),
		Klartext:  g(fields, "STICHWORT_KLARTEXT"),
		Meldung:   g(fields, "MELDUNG"),
		Objekt:    g(fields, "OBJEKTNAME"),
		Strasse:   g(fields, "STRASSE"),
		HNR:       g(fields, "HAUSNUMMER"),
		Ort:       g(fields, "ORT"),
		Mittel:    cleanMittel(g(fields, "EINSATZMITTEL")),
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return
	}

	req, err := http.NewRequest(http.MethodPost,
		cfg.EDPApiURL+"/api/v1/alarmierung", bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := client.Do(req)
	if err != nil {
		logAlarmError("%v", err)
		return
	}
	defer resp.Body.Close()

	if cfg.Console {
		fmt.Printf("[ALARM] EDP-API HTTP %d → ISSI %s\n", resp.StatusCode, vehicleID)
	}
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

func main() {
	args := os.Args[1:]
	writeDiagnostic(args)

	cfg := loadConfig()

	// EDP-Wert-Prefix überspringen wenn konfiguriert
	if cfg.EDPValue && len(args) > 1 {
		args = args[1:]
	}

	var entry string
	var fields map[string]string
	var vehicleID string

	switch {
	case len(args) == 0 || args[0] == "":
		entry = fmt.Sprintf("[%s] WARNUNG: Kein Argument übergeben.",
			time.Now().Format("2006-01-02 15:04:05"))
	default:
		var pipeArg string
		if len(args) == 1 {
			pipeArg = args[0]
		} else {
			pipeArg = args[len(args)-1]
			vehicleID = strings.TrimSpace(strings.Join(args[:len(args)-1], " "))
		}
		fields = parseFields(pipeArg)
		entry = formatEntry(fields, cfg, vehicleID)
	}

	lp := logPath(cfg)
	if err := writeLog(lp, entry); err != nil {
		writeFallback(lp, err, entry)
		os.Exit(1)
	}

	// Gerät mit der ISSI (vehicleID) über die EDP-API alarmieren
	if fields != nil {
		sendAlarm(fields, vehicleID, cfg)
	}

	if cfg.Console {
		fmt.Printf("[OK] %s\n%s\n", lp, entry)
	}
}
