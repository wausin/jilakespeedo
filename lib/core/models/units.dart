/// Speed units supported by the app.
enum SpeedUnit { kmh, mph }

/// Converts a speed from m/s to the given unit.
double convertSpeed({required double ms, required SpeedUnit unit}) {
  switch (unit) {
    case SpeedUnit.kmh:
      return ms * 3.6;
    case SpeedUnit.mph:
      return ms * 2.2369362920544;
  }
}

/// Converts a distance from meters to the given unit's distance measure
/// (km for kmh, miles for mph).
double convertDistance({required double meters, required SpeedUnit unit}) {
  switch (unit) {
    case SpeedUnit.kmh:
      return meters / 1000;
    case SpeedUnit.mph:
      return meters / 1609.344;
  }
}

/// Display label for a speed unit.
String unitLabel(SpeedUnit unit) {
  switch (unit) {
    case SpeedUnit.kmh:
      return 'km/h';
    case SpeedUnit.mph:
      return 'mph';
  }
}
