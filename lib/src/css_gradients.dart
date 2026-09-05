import 'dart:math' as math;

import 'package:flutter/material.dart';

/// CSS gradient angles run clockwise from "to top" (`0deg` points up), while
/// Flutter's [Alignment] axis runs x-right / y-down. These map one onto the
/// other so angles can be copied straight out of the design.
Alignment cssAngleBegin(double degrees) {
  final radians = degrees * math.pi / 180;
  return Alignment(-math.sin(radians), math.cos(radians));
}

Alignment cssAngleEnd(double degrees) {
  final radians = degrees * math.pi / 180;
  return Alignment(math.sin(radians), -math.cos(radians));
}
