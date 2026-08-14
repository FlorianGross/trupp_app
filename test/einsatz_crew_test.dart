import 'package:flutter_test/flutter_test.dart';
import 'package:trupp_app/data/edp_api.dart';
import 'package:trupp_app/data/einsatz_crew.dart';

void main() {
  const geraete = [
    EdpTetraEndgeraet(issi: '1001', rufname: 'Florian München 1/44/1'),
    EdpTetraEndgeraet(issi: '1002', rufname: 'Florian München 1/44/2'),
    EdpTetraEndgeraet(issi: '1003'), // ohne Rufname
  ];

  EdpEinsatzmittel mittel(
    String rufname, {
    String? einsatznummer,
    String? status,
    int? besatzung,
    String? abschnitt,
    String? typ,
  }) =>
      EdpEinsatzmittel(
        rufname: rufname,
        einsatznummer: einsatznummer,
        status: status,
        besatzungGes: besatzung,
        abschnitt: abschnitt,
        typ: typ,
      );

  group('ownRufname', () {
    test('findet den Rufnamen zur eigenen ISSI', () {
      expect(EinsatzCrewResolver.ownRufname(geraete, '1002'),
          'Florian München 1/44/2');
    });

    test('unbekannte ISSI → null', () {
      expect(EinsatzCrewResolver.ownRufname(geraete, '9999'), isNull);
    });

    test('Gerät ohne Rufname → null', () {
      expect(EinsatzCrewResolver.ownRufname(geraete, '1003'), isNull);
    });

    test('leere ISSI → null', () {
      expect(EinsatzCrewResolver.ownRufname(geraete, ''), isNull);
    });
  });

  group('ownEinsatznummer', () {
    final alle = [
      mittel('Florian München 1/44/1', einsatznummer: '4711'),
      mittel('Florian München 1/44/2', einsatznummer: '4712'),
      mittel('Florian München 2/44/1'), // keinem Einsatz zugeordnet
    ];

    test('liefert den Einsatz des eigenen Fahrzeugs', () {
      expect(
        EinsatzCrewResolver.ownEinsatznummer(alle, 'Florian München 1/44/2'),
        '4712',
      );
    });

    test('eigenes Fahrzeug ohne Einsatz → null', () {
      expect(
        EinsatzCrewResolver.ownEinsatznummer(alle, 'Florian München 2/44/1'),
        isNull,
      );
    });

    test('eigenes Fahrzeug nicht in der Liste → null', () {
      expect(EinsatzCrewResolver.ownEinsatznummer(alle, 'Unbekannt'), isNull);
    });
  });

  group('crewFor', () {
    final alle = [
      mittel('Florian München 1/44/1', einsatznummer: '4711', status: '3'),
      mittel('Florian München 1/11/1', einsatznummer: '4711', status: '4'),
      // Fremder Einsatz — darf nicht auftauchen.
      mittel('Florian München 9/99/9', einsatznummer: '4712', status: '1'),
      // Ohne Einsatz — darf ebenfalls nicht auftauchen.
      mittel('Florian München 8/88/8', status: '2'),
      // Ohne Rufname — waere eine leere Zeile im Display.
      mittel('', einsatznummer: '4711', status: '1'),
    ];

    test('zeigt nur die am selben Einsatz beteiligten Fahrzeuge', () {
      final crew = EinsatzCrewResolver.crewFor(alle, '4711');
      expect(crew.map((c) => c.rufname), [
        'Florian München 1/11/1',
        'Florian München 1/44/1',
      ]);
    });

    test('eigenes Fahrzeug steht oben und ist markiert', () {
      final crew = EinsatzCrewResolver.crewFor(alle, '4711',
          ownRufname: 'Florian München 1/44/1');
      expect(crew.first.rufname, 'Florian München 1/44/1');
      expect(crew.first.isOwn, isTrue);
      expect(crew[1].isOwn, isFalse);
    });

    test('unbekannter Einsatz → leer', () {
      expect(EinsatzCrewResolver.crewFor(alle, '0000'), isEmpty);
    });
  });

  group('CrewMember.detail', () {
    test('setzt Status, Besatzung und Abschnitt zusammen', () {
      final m = EinsatzCrewResolver.crewFor(
        [
          mittel('ELW 1',
              einsatznummer: '1', status: '3', besatzung: 6, abschnitt: 'Ost')
        ],
        '1',
      ).single;
      expect(m.detail, 'Status 3 • Bes. 6 • Ost');
    });

    test('faellt auf den Fahrzeugtyp zurueck, wenn sonst nichts bekannt ist', () {
      final m = EinsatzCrewResolver.crewFor(
        [mittel('ELW 1', einsatznummer: '1', typ: 'ELW')],
        '1',
      ).single;
      expect(m.detail, 'ELW');
    });

    test('Besatzung 0 wird nicht angezeigt', () {
      final m = EinsatzCrewResolver.crewFor(
        [mittel('ELW 1', einsatznummer: '1', status: '3', besatzung: 0)],
        '1',
      ).single;
      expect(m.detail, 'Status 3');
    });

    test('ohne jede Angabe bleibt die Zeile leer', () {
      final m = EinsatzCrewResolver.crewFor(
        [mittel('ELW 1', einsatznummer: '1')],
        '1',
      ).single;
      expect(m.detail, '');
    });
  });
}
