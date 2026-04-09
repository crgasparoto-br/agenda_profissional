# Mobile App (Flutter)

Aplicativo mobile do profissional com fluxo MVP:

- Login com Supabase Auth
- Onboarding (chama `bootstrap-tenant`)
- Agenda diária simples
- Criação de agendamento (chama `create-appointment`)

## Requisitos

- Flutter 3.24+
- Dart 3.5+

## Instalação

```bash
cd apps/mobile
flutter pub get
```

## Executar

```bash
flutter run \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

### Android físico na mesma rede Wi-Fi

```bash
flutter run -d <DEVICE_ID> \
  --dart-define=SUPABASE_URL=http://<SEU_IP_LOCAL>:54321 \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

## Observações

- Para Android Emulator, use `10.0.2.2` no lugar de `127.0.0.1`.
- Para Android físico, `127.0.0.1` e `10.0.2.2` não funcionam. Use o IP local da máquina que está rodando o Supabase.
- Sessão é persistida automaticamente pelo `supabase_flutter`.
- Se a web estiver em um projeto Supabase diferente, passe `SUPABASE_URL` e `SUPABASE_ANON_KEY` no `flutter run` para usar o mesmo backend.

