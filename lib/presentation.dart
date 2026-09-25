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
