String displayName(String value) {
  switch (value.trim().toLowerCase()) {
    case 'development viewer':
      return 'Viewer';
    case 'development admin':
      return 'Admin';
    case 'development superadmin':
      return 'Superadmin';
    default:
      return value;
  }
}

String displayRole(String value) => switch (value.trim().toUpperCase()) {
      'VIEWER' => 'Viewer',
      'ADMIN' => 'Admin',
      'SUPERADMIN' => 'Superadmin',
      _ => value,
    };

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatLocalTimestamp(DateTime instant) {
  final local = instant.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]} ${local.year}, $hour:$minute';
}

String formatLocalDate(DateTime instant) {
  final local = instant.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}
