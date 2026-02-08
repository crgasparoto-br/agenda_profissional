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

## Observações

- Para Android Emulator, use `10.0.2.2` no lugar de `127.0.0.1`.
- Sessão é persistida automaticamente pelo `supabase_flutter`.

