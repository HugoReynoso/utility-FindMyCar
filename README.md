# ParkFinder - Trova la mia macchina

App Flutter MVP per Android, progettata per essere portata anche su iOS.

## Funzioni incluse

- Permesso posizione richiesto solo quando premi **Salva posizione**.
- Salvataggio locale con DataStore Preferences su Android tramite `SharedPreferencesAsync`.
- Distanza dalla posizione attuale alla macchina salvata.
- Apertura di Google Maps verso la posizione salvata.
- Localizzazione UI in italiano, inglese, spagnolo, cinese, francese, tedesco e arabo.
- Gestione errori per GPS disattivato, permesso negato e nessuna posizione salvata.

## Avvio

```powershell
flutter pub get
flutter run
```

Su Android serve un dispositivo fisico o emulatore con servizi posizione attivi.
