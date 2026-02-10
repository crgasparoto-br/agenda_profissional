import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/appointment.dart';

void main() {
  test('CreateAppointmentInput serializes dates as UTC ISO', () {
    final input = CreateAppointmentInput(
      clientId: null,
      clientName: null,
      clientPhone: null,
      serviceId: 'service-1',
      startsAt: DateTime.utc(2026, 2, 8, 13, 0),
      endsAt: DateTime.utc(2026, 2, 8, 13, 30),
      professionalId: null,
      anyAvailable: true,
    );

    final json = input.toJson();

    expect(json['client_id'], isNull);
    expect(json['client_name'], isNull);
    expect(json['client_phone'], isNull);
    expect(json['service_id'], 'service-1');
    expect(json['starts_at'], '2026-02-08T13:00:00.000Z');
    expect(json['ends_at'], '2026-02-08T13:30:00.000Z');
    expect(json['professional_id'], isNull);
    expect(json['any_available'], true);
    expect(json['source'], 'professional');
  });

  test('AppointmentItem parses nested fields with defaults', () {
    final item = AppointmentItem.fromJson({
      'id': 'appt-1',
      'professional_id': 'prof-1',
      'starts_at': '2026-02-08T13:00:00.000Z',
      'ends_at': '2026-02-08T13:30:00.000Z',
      'status': 'scheduled',
      'professionals': {'name': 'Dr. A'},
      'services': {'name': 'Consulta'},
      'clients': null,
    });

    expect(item.id, 'appt-1');
    expect(item.professionalId, 'prof-1');
    expect(item.status, 'scheduled');
    expect(item.professionalName, 'Dr. A');
    expect(item.serviceName, 'Consulta');
    expect(item.clientName, 'Sem cliente');
  });
}

