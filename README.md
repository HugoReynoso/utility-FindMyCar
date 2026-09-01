# FindMyCar - Trovo la mia auto
[Demo](https://hugoreynoso.github.io/utility-FindMyCar/)

FindMyCar e un'app Flutter per Android pensata per memorizzare la posizione dell'auto e ritrovarla rapidamente con una mappa interna. Il progetto e gia strutturato per poter essere portato anche su iOS in futuro.

## Funzioni principali

- Memorizza la posizione precisa dell'auto solo quando l'utente preme **Memorizza posizione auto**.
- Salva localmente latitudine, longitudine, precisione GPS, data/ora, nota opzionale, foto e preferito.
- Mostra la mappa interna con due marker: posizione dell'auto e posizione attuale dell'utente.
- Permette di aprire Google Maps per navigazione esterna.
- Cronologia di tutte le posizioni salvate.
- Preferiti per parcheggi importanti o ricorrenti.
- Condivisione della posizione tramite WhatsApp, messaggi o altre app.
- Lingua automatica con cambio manuale in app.
- Tema chiaro/scuro/sistema e personalizzazione colore.

## Demo

Apri la demo visuale della Home direttamente dal repository:

[Visualizza demo pubblicata](https://hugoreynoso.github.io/utility-FindMyCar/)

La demo mostra la direzione UI/UX della schermata principale: header, spazio pubblicita, due card principali e navigazione inferiore.

## Avvio locale

```powershell
flutter pub get
flutter run
```

Per la migliore precisione GPS usa un telefono Android reale con servizi di posizione attivi.

## Persistenza dati

La posizione salvata resta disponibile anche se il telefono si spegne o si riavvia. I dati vengono persi solo se l'utente disinstalla l'app, cancella i dati dell'app dalle impostazioni Android o resetta il telefono.

## Creato da

Created by Reynoso Studios

