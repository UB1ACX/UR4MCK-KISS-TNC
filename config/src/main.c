/*************************************************
			AVR TNC SETUP TOOL
		Version 0.0.2 20.08.2006
			(c) 2006 UR4MCK

		This program is FREEWARE
 See updates at http://daemon.co.ua/projects
***************************************************/

#include <windows.h>
#include <stdio.h>
#include "resource.h"

#define BUF_LEN					256
#define DEF_TXDELAY				64
#define DEF_TXTAIL				16
#define DEF_PERSIST				63
#define DEF_SLOTTIME			10
#define DEF_UART_RATE			57600

#define SYS_CLK					16000000

#define WM_USER_CHECK_CHANGES	(WM_USER + 1)

#define UART_RATE_MIN			2400
#define UART_RATE_MAX			115200

/* KISS special symbols */
#define KISS_FEND				0xc0
#define KISS_FESC				0xdb
#define KISS_TFEND				0xdc
#define KISS_TFESC				0xdd
#define KISS_CMD_SETHW			0x06

/* KISS 'Set hardware' adresses */
#define KISS_HW_UBRL			0x80
#define KISS_HW_UBRH			0x81
#define KISS_HW_L1				0x90

typedef unsigned int	uint;
typedef unsigned char	u8;

typedef struct {
		uint	val;
		BOOL	ok;
} AX25_SETTINGS;

HINSTANCE		hInst;
HANDLE			hCom;
char			*Port[] = {"COM1", "COM2", "COM3", "COM4"};
char			*Rate[] = {"2400", "4800", "9600", "19200", "38400", "56000", "57600", "115200"};
u8				kiss_sample[] = {KISS_FEND, 0x00,													/* KISS header */
								 'T' << 1, 'E' << 1, 'S' << 1, 'T' << 1, 0x40, 0x40, 0x60,			/* To address */
								 'A' << 1, 'V' << 1, 'R' << 1, 'T' << 1, 'N' << 1, 'C' << 1, 0x61,	/* From address */
								 0x03, 0xf0,														/* UI-frame */
								 'T', 'h', 'i', 's', ' ', 'i', 's', ' ', 'a',						/* Message */
								 ' ', 't', 'e', 's', 't', '.',										/* Message */
								 KISS_FEND};														/* KISS footer */
AX25_SETTINGS	ax25[5];
u8				kiss_buf[BUF_LEN];
int				kiss_len;
DWORD			n;
uint			uart_rate = 57600;

LRESULT CALLBACK MainDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM lParam);
LRESULT CALLBACK AboutDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM lParam);
void FillComboBox(HWND hDlg, int Ctl, char **str,WORD len, int select);
void SettingsUpdate(HWND hDlg, WPARAM param, LPARAM num);
void add_kiss(int n);
int open_port(char *name);
void close_port(void);

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, PSTR szCmdLine, int iCmdShow) {
	hInst = hInstance;

	DialogBox(hInst, MAKEINTRESOURCE(IDD_MAIN), NULL, MainDlgProc);
	return 0;
}

LRESULT CALLBACK MainDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM lParam) {
	int		i;
	char	s[64], s1[8];

	switch (msg) {
		case WM_COMMAND:
			switch (wParam) {
				case IDC_EXIT:
				case WM_DESTROY:
						close_port();
						EndDialog(hDlg, msg);
						PostQuitMessage(0);
						break;

				case IDC_ABOUT:
						DialogBox(hInst, MAKEINTRESOURCE(IDD_ABOUT), hDlg, AboutDlgProc);
						break;

				case IDC_TRANSMIT_KISS:
						memcpy(kiss_buf, kiss_sample, sizeof(kiss_sample));
						kiss_len = sizeof(kiss_sample);
						goto kiss_send;

				case IDC_SET_VALUES:
						/* Get current values */
						for (i = 1; i < 6; i++)
							SendMessage(hDlg, WM_USER_CHECK_CHANGES, 0, i);

						/* Reset buffer */
						memset(kiss_buf, 0x00, BUF_LEN);
						kiss_len = 0;

						/* Check which value is queued to send */
						for (i = 0; i < 4; i++)
							if (ax25[i + 1].ok && IsDlgButtonChecked(hDlg, IDC_SET_TXDELAY + i) == BST_CHECKED) {
									/* Add KISS packet to a buffer */
									add_kiss(i);
							}

						/* Check if need to store AX.25 L1 params in EEPROM */
						if (IsDlgButtonChecked(hDlg, IDC_SET_IN_EEPROM) == BST_CHECKED) {
							add_kiss(5); /* Add 'Set hardware' KISS command with address 0x90 (store L1) */
						}

						/* Check if need to store new UART rate in EEPROM */
						if (ax25[0].ok && IsDlgButtonChecked(hDlg, IDC_SET_NEW_RATE) == BST_CHECKED) {
							add_kiss(6); /* Add two 'Set hardware' KISS commands with addresses 0x80, 0x81 (store UART rate) */
						}

						if (kiss_len == 0) {
							MessageBox(hDlg, "Nothing to send", "Warning", MB_OK | MB_ICONINFORMATION); 
						} else {
							/* Send queued data from buffer */
kiss_send:
							/* Compose port name */
							GetDlgItemText(hDlg, IDC_PORT, (LPSTR)s1, sizeof(s1));
							strcpy(s, "\\\\.\\");
							strcat(s, s1);
							if (open_port(s) != 0) {
								strcpy(s, "Couldn't open port ");
								strcat(s, s1);
								MessageBox(hDlg, s, "Warning", MB_OK | MB_ICONSTOP); 
								break;
							}

							/* Send data */
							if (!WriteFile(hCom, kiss_buf, kiss_len, &n, NULL))
								MessageBox(hDlg, "WriteFile() failed", "Warning", MB_OK | MB_ICONSTOP);
							else MessageBox(hDlg, "OK", "Info", MB_OK | MB_ICONINFORMATION);
							close_port();

							/* Use new rate in IDC_RATE (if active) */
							if (IsDlgButtonChecked(hDlg, IDC_SET_NEW_RATE)) {
								GetDlgItemText(hDlg, IDC_NEW_RATE, (LPSTR)s, sizeof(s));
								SendDlgItemMessage(hDlg, IDC_RATE, CB_SELECTSTRING, 0, (LPARAM)(LPSTR)s);
								SettingsUpdate(hDlg, 0, 0);
							}
						}
						break;

				case IDC_GET_VALUES:
						MessageBox(hDlg, "Get Values", "Debug", MB_OK);

						/* TODO */

						break;

				/* Rate */
				case ((CBN_SELCHANGE << 16) | IDC_RATE):
				case ((CBN_EDITUPDATE << 16) | IDC_RATE):
						PostMessage(hDlg, WM_USER_CHECK_CHANGES, 0, 0);
						break;
				case ((CBN_KILLFOCUS << 16) | IDC_RATE):
						PostMessage(hDlg, WM_USER_CHECK_CHANGES, 1, 0);
						break;
				case ((CBN_SELCHANGE << 16) | IDC_NEW_RATE):
				case ((CBN_EDITUPDATE << 16) | IDC_NEW_RATE):
						PostMessage(hDlg, WM_USER_CHECK_CHANGES, 0, 1);
						break;

				/* New rate */
				case ((CBN_KILLFOCUS << 16) | IDC_NEW_RATE):
						PostMessage(hDlg, WM_USER_CHECK_CHANGES, 1, 1);
						break;
				case IDC_SET_NEW_RATE:
						if (IsDlgButtonChecked(hDlg, IDC_SET_NEW_RATE) == BST_CHECKED)
							EnableWindow(GetDlgItem(hDlg, IDC_NEW_RATE), TRUE);
						else EnableWindow(GetDlgItem(hDlg, IDC_NEW_RATE), FALSE);
						break;

				/* TX Delay */
				case ((EN_KILLFOCUS << 16) | IDC_TXDELAY):
						PostMessage(hDlg, WM_USER_CHECK_CHANGES, 1, 2);
						break;
				case IDC_SET_TXDELAY:
						if (IsDlgButtonChecked(hDlg, IDC_SET_TXDELAY) == BST_CHECKED)
							EnableWindow(GetDlgItem(hDlg, IDC_TXDELAY), TRUE);
						else EnableWindow(GetDlgItem(hDlg, IDC_TXDELAY), FALSE);
						break;


				/* TX Tail */
				case ((EN_KILLFOCUS << 16) | IDC_TXTAIL):
						PostMessage(hDlg, WM_USER_CHECK_CHANGES, 1, 5);
						break;
				case IDC_SET_TXTAIL:
						if (IsDlgButtonChecked(hDlg, IDC_SET_TXTAIL) == BST_CHECKED)
							EnableWindow(GetDlgItem(hDlg, IDC_TXTAIL), TRUE);
						else EnableWindow(GetDlgItem(hDlg, IDC_TXTAIL), FALSE);
						break;

				/* Persistence */
				case ((EN_KILLFOCUS << 16) | IDC_PERSIST):
						PostMessage(hDlg, WM_USER_CHECK_CHANGES, 1, 3);
						break;
				case IDC_SET_PERSIST:
						if (IsDlgButtonChecked(hDlg, IDC_SET_PERSIST) == BST_CHECKED)
							EnableWindow(GetDlgItem(hDlg, IDC_PERSIST), TRUE);
						else EnableWindow(GetDlgItem(hDlg, IDC_PERSIST), FALSE);
						break;

				/* Slot time */
				case ((EN_KILLFOCUS << 16) | IDC_SLOTTIME):
						PostMessage(hDlg, WM_USER_CHECK_CHANGES, 1, 4);
						break;
				case IDC_SET_SLOTTIME:
						if (IsDlgButtonChecked(hDlg, IDC_SET_SLOTTIME) == BST_CHECKED)
							EnableWindow(GetDlgItem(hDlg, IDC_SLOTTIME), TRUE);
						else EnableWindow(GetDlgItem(hDlg, IDC_SLOTTIME), FALSE);
						break;
			}
			break;

		case WM_USER_CHECK_CHANGES:
				SettingsUpdate(hDlg, wParam, lParam);
				break;

		case WM_INITDIALOG:
				/* Set default AX.25 channel access parameter values */
				SetDlgItemInt(hDlg, IDC_TXDELAY, DEF_TXDELAY, FALSE);
				SetDlgItemInt(hDlg, IDC_TXTAIL, DEF_TXTAIL, FALSE);
				SetDlgItemInt(hDlg, IDC_PERSIST, DEF_PERSIST, FALSE);
				SetDlgItemInt(hDlg, IDC_SLOTTIME, DEF_SLOTTIME, FALSE);
				CheckDlgButton(hDlg, IDC_SET_TXDELAY, 1);

				/* Set default communication parameters */
				FillComboBox(hDlg, IDC_PORT, Port, 4, 0);
				FillComboBox(hDlg, IDC_RATE, Rate, 8, 6);
				FillComboBox(hDlg, IDC_NEW_RATE, Rate, 8, 6);
				SettingsUpdate(hDlg, 0, 0);

				SetFocus(GetDlgItem(hDlg, IDC_PORT));

				hCom = NULL;
	}
	return 0;
}

LRESULT CALLBACK AboutDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM lParam) {

	if (msg == WM_COMMAND && (wParam == IDC_OK || wParam == WM_DESTROY)) EndDialog(hDlg, msg);
	return 0;
}

void FillComboBox(HWND hDlg, int Ctl, char **str,WORD len, int select) {
    int i;

    for (i = 0; i < len; i++) SendDlgItemMessage(hDlg, Ctl, CB_ADDSTRING, 0, (LPARAM)(LPSTR)str[i]);
	SendDlgItemMessage(hDlg, Ctl, CB_SETCURSEL, (WPARAM)select, 0L ) ;
}

void SettingsUpdate(HWND hDlg, WPARAM param, LPARAM num) {
uint			tmp;
int				ctl;
char			*p, str[64], tstr[128];
AX25_SETTINGS	*v;

		switch (num) {
			case 0:		ctl = IDC_RATE; break;
			case 1:		ctl = IDC_NEW_RATE; v = &ax25[0]; break;
			case 2:		ctl = IDC_TXDELAY; v = &ax25[1]; break;
			case 3:		ctl = IDC_PERSIST; v = &ax25[2]; break;
			case 4:		ctl = IDC_SLOTTIME; v = &ax25[3]; break;
			case 5:		ctl = IDC_TXTAIL; v = &ax25[4]; break;
			default:	return;
		}

		/* Get and convert input */
		GetDlgItemText(hDlg, ctl, (LPSTR)str, sizeof(str));
		tmp = (uint)strtoul(str, &p, 0);

		/* Check input */
		if (param == 1) {

			/* Check for integer number */
			if (p != (str + strlen(str))) {
				MessageBox(hDlg, "Illegal number", "Warning", MB_OK | MB_ICONSTOP);
				SetFocus(GetDlgItem(hDlg, ctl));
				return;
			}

			/* Check for boundaries */
			switch (num) {
				case 0:
				case 1:
						if (tmp < UART_RATE_MIN || tmp > UART_RATE_MAX) {
							MessageBox(hDlg, "Unsupported baud rate", "Warning", MB_OK | MB_ICONSTOP);
							SetFocus(GetDlgItem(hDlg, ctl));
							return;
						}
						break;

				default:
						if (num < 6) {
							if (tmp == 0 || tmp > 255) {
								switch (num) {
									case 2:
											strcpy(str, "TX Delay");
											break;
									
									case 3:
											strcpy(str, "Persistence");
											break;
											
									case 4:
											strcpy(str, "Slot time");
											break;

									case 5:
											strcpy(str, "TX Tail");
											break;

									default:strcpy(str, "a");
								}

								sprintf(tstr, "Enter %s value in range 1...255", str);
								MessageBox(hDlg, tstr, "Warning", MB_OK | MB_ICONSTOP);
								SetFocus(GetDlgItem(hDlg, ctl));
							}
						}
			}
		}

		if (num == 0) {
			/* Show current port settings */
			sprintf(str, "Port settings: %u, 8, N, 1", tmp);
			SetDlgItemText(hDlg, IDC_PORT_SETTINGS, (LPSTR)str);
			uart_rate = tmp;
		} else {
			v->val = tmp;
			v->ok = TRUE;
		}
}

void add_kiss(int n) {
	int i, r;

	i = kiss_len;
	kiss_buf[i++] = KISS_FEND;

	switch (n) {
		case 5:
				/* Command to store AX.25 L1 params in EEPROM */
				
				kiss_buf[i++] = KISS_CMD_SETHW;
				kiss_buf[i++] = KISS_HW_L1;
				kiss_buf[i++] = 0; /* dummy */
				break;

		case 6:
				/* UART new rate */

				r = SYS_CLK / 16 / ax25[0].val; /* Calculate baudrate divisor */

				/* Set UBRL */
				kiss_buf[i++] = KISS_CMD_SETHW;
				kiss_buf[i++] = KISS_HW_UBRL;
				kiss_buf[i++] = (u8)(r & 0x000000ff);
				kiss_buf[i++] = KISS_FEND;

				/* Set UBRH */
				kiss_buf[i++] = KISS_FEND;
				kiss_buf[i++] = KISS_CMD_SETHW;
				kiss_buf[i++] = KISS_HW_UBRH;
				kiss_buf[i++] = (u8)((r & 0x0000ff00) >> 8);
				break;

		default:
				if (n >= 0 && n < 4) {
					/* Usual L1 AX.25 params */
					n++;
					kiss_buf[i++] = (u8)n;
					if (ax25[n].val == (uint)KISS_FEND) {
							kiss_buf[i++] = KISS_FESC;
							kiss_buf[i++] = KISS_TFEND;
					} else if (ax25[n].val == (uint)KISS_FESC) {
								kiss_buf[i++] = KISS_FESC;
								kiss_buf[i++] = KISS_TFESC;
							} else kiss_buf[i++] = (u8)ax25[n].val;
				}
	}

	kiss_buf[i++] = KISS_FEND;
	kiss_len = i;
}

int open_port(char *name) {
	DCB 	dcb;

	/* Open port */
	if ((hCom = CreateFile(name, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL)) == INVALID_HANDLE_VALUE) return -1;

	if (!GetCommState(hCom, &dcb)) return -2;

	/* Set COM parameters */
	dcb.BaudRate = uart_rate;
	dcb.ByteSize = 8;
	dcb.Parity = NOPARITY;
	dcb.StopBits = ONESTOPBIT;
	if (!SetCommState(hCom, &dcb)) return -3;

	return 0;
}

void close_port(void) {

	if (hCom != NULL) {
		CloseHandle(hCom);
		hCom = NULL;
	}
}
