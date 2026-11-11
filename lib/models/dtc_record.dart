class DtcCode {
  final String code;
  final bool isPending;
  final String? customDescription;

  const DtcCode({
    required this.code,
    this.isPending = false,
    this.customDescription,
  });

  String get system {
    if (code.isEmpty) return 'Unknown';
    switch (code[0].toUpperCase()) {
      case 'P':
        return 'Powertrain (เครื่องยนต์และระบบส่งกำลัง)';
      case 'C':
        return 'Chassis (ช่วงล่างและระบบเบรก ABS)';
      case 'B':
        return 'Body (ตัวถังและระบบปรับอากาศ/ถุงลมนิรภัย)';
      case 'U':
        return 'Network (ระบบสื่อสาร CAN Bus/กล่อง ECU)';
      default:
        return 'OBD-II System';
    }
  }

  String get description {
    if (customDescription != null && customDescription!.isNotEmpty) {
      return customDescription!;
    }
    return kCommonDtcDefinitions[code] ??
        'Standard OBD-II Diagnostic Trouble Code ($code). Tap Search to view repair procedures.';
  }

  String get googleSearchUrl =>
      'https://www.google.com/search?q=OBD2+code+$code+meaning+symptoms+repair';

  Map<String, dynamic> toJson() => {
        'code': code,
        'isPending': isPending,
        'description': description,
      };

  factory DtcCode.fromJson(Map<String, dynamic> json) => DtcCode(
        code: json['code'] as String? ?? 'P0000',
        isPending: json['isPending'] as bool? ?? false,
        customDescription: json['description'] as String?,
      );
}

class DtcDiagnosticReport {
  final String id;
  final String timestampFormatted;
  final bool milActive;
  final List<DtcCode> codes;

  const DtcDiagnosticReport({
    required this.id,
    required this.timestampFormatted,
    required this.milActive,
    required this.codes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestampFormatted': timestampFormatted,
        'milActive': milActive,
        'codes': codes.map((c) => c.toJson()).toList(),
      };

  factory DtcDiagnosticReport.fromJson(Map<String, dynamic> json) =>
      DtcDiagnosticReport(
        id: json['id'] as String? ?? '',
        timestampFormatted: json['timestampFormatted'] as String? ?? '',
        milActive: json['milActive'] as bool? ?? false,
        codes: (json['codes'] as List<dynamic>?)
                ?.map((c) => DtcCode.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

const Map<String, String> kCommonDtcDefinitions = {
  // Air / Fuel
  'P0100': 'Mass or Volume Air Flow Circuit Malfunction (แอร์โฟร์เซนเซอร์ขัดข้อง)',
  'P0101': 'Mass Air Flow Sensor Circuit Range/Performance (การทำงานของแอร์โฟร์ผิดปกติ)',
  'P0102': 'Mass Air Flow Circuit Low Input (สัญญาณแอร์โฟร์ต่ำเกินไป)',
  'P0103': 'Mass Air Flow Circuit High Input (สัญญาณแอร์โฟร์สูงเกินไป)',
  'P0106': 'MAP/Barometric Pressure Circuit Range/Performance (แมพเซนเซอร์ค่าผิดปกติ)',
  'P0107': 'MAP Sensor Circuit Low Input (สัญญาณแรงดัน MAP ต่ำ)',
  'P0108': 'MAP Sensor Circuit High Input (สัญญาณแรงดัน MAP สูง)',
  'P0113': 'Intake Air Temperature Circuit High (อุณหภูมิไอดีสูงเกิน)',
  'P0115': 'Engine Coolant Temperature Circuit Malfunction (เซนเซอร์อุณหภูมิน้ำขัดข้อง)',
  'P0118': 'Coolant Temperature Circuit High Input (สัญญาณความร้อนน้ำสูงผิดปกติ)',
  'P0120': 'Throttle Position Sensor Circuit Malfunction (เซนเซอร์ลิ้นปีกผีเสื้อขัดข้อง)',
  'P0128': 'Coolant Thermostat Error (วาล์วน้ำเปิดค้างหรือทำงานผิดปกติ)',
  // Oxygen Sensors
  'P0130': 'O2 Sensor Circuit Malfunction Bank 1 Sensor 1 (ออกซิเจนเซนเซอร์ตัวหน้าขัดข้อง)',
  'P0133': 'O2 Sensor Circuit Slow Response Bank 1 Sensor 1 (ออกซิเจนเซนเซอร์ตอบสนองช้า)',
  'P0135': 'O2 Sensor Heater Circuit Malfunction Bank 1 Sensor 1 (ระบบฮีตเตอร์เซนเซอร์ไอเสียขัดข้อง)',
  'P0141': 'O2 Sensor Heater Circuit Bank 1 Sensor 2 (ระบบฮีตเตอร์เซนเซอร์ตัวหลังขัดข้อง)',
  'P0171': 'System Too Lean Bank 1 (ส่วนผสมน้ำมันบางเกินไป)',
  'P0172': 'System Too Rich Bank 1 (ส่วนผสมน้ำมันหนาเกินไป)',
  // Ignition & Misfire
  'P0300': 'Random / Multiple Cylinder Misfire Detected (เครื่องยนต์จุดระเบิดผิดพลาดหลายสูบ)',
  'P0301': 'Cylinder 1 Misfire Detected (สูบ 1 จุดระเบิดผิดพลาด/สะดุด)',
  'P0302': 'Cylinder 2 Misfire Detected (สูบ 2 จุดระเบิดผิดพลาด/สะดุด)',
  'P0303': 'Cylinder 3 Misfire Detected (สูบ 3 จุดระเบิดผิดพลาด/สะดุด)',
  'P0304': 'Cylinder 4 Misfire Detected (สูบ 4 จุดระเบิดผิดพลาด/สะดุด)',
  'P0325': 'Knock Sensor 1 Circuit Malfunction (น็อคเซนเซอร์ขัดข้อง)',
  'P0335': 'Crankshaft Position Sensor A Circuit Malfunction (เซนเซอร์เพลาข้อเหวี่ยงขัดข้อง)',
  'P0340': 'Camshaft Position Sensor Circuit Malfunction (เซนเซอร์เพลาราวลิ้นขัดข้อง)',
  // Emissions / Catalyst / EVAP
  'P0401': 'Exhaust Gas Recirculation (EGR) Flow Insufficient (ระบบ EGR ไหลไม่เพียงพอ)',
  'P0420': 'Catalyst System Efficiency Below Threshold Bank 1 (ประสิทธิภาพแคตตาไลติกคอนเวอร์เตอร์ต่ำ)',
  'P0430': 'Catalyst System Efficiency Below Threshold Bank 2 (ประสิทธิภาพแคตตาไลติกต่ำ Bank 2)',
  'P0440': 'Evaporative Emission System Malfunction (ระบบระบายไอน้ำมันถังขัดข้อง)',
  'P0442': 'EVAP System Small Leak Detected (พบไอน้ำมันรั่วซึมขนาดเล็ก)',
  'P0455': 'EVAP System Gross Leak Detected (พบไอน้ำมันรั่วขนาดใหญ่/ฝาถังน้ำมันปิดไม่สนิท)',
  // Transmission
  'P0500': 'Vehicle Speed Sensor Malfunction (เซนเซอร์ความเร็วรถยนต์ขัดข้อง)',
  'P0700': 'Transmission Control System Malfunction (กล่องควบคุมเกียร์ขัดข้อง)',
};
