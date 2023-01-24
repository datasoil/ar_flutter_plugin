// The code in this file is adapted from Oleksandr Leuschenko' ARKit Flutter Plugin (https://github.com/olexale/arkit_flutter_plugin)

import 'package:ar_flutter_plugin/utils/json_converters.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:json_annotation/json_annotation.dart';
import 'dart:math' as math;

/// ARNode is the model class for node-tree objects.
/// It encapsulates the position, rotations, and other transforms of a node, which define a coordinate system.
/// The coordinate systems of all the sub-nodes are relative to the one of their parent node.
class ARNode {
  ARNode({
    String? name,
    Vector3? position,
    Vector3? scale,
    Vector4? rotation,
    Vector3? eulerAngles,
    Matrix4? transformation,
    Map<String, dynamic>? data,
    Map<String, dynamic>? asset,
  })  : name = name ?? UniqueKey().toString(),
        transformNotifier = ValueNotifier(createTransformMatrix(
            transformation, position, scale, rotation, eulerAngles)),
        asset = asset ?? null,
        data = data ?? null;

  /// Specifies the path to the 3D model used for the [ARNode]. Depending on the [type], this is either a relative path or an URL to an online asset
  String? uri;

  /// Determines the receiver's transform.
  /// The transform is the combination of the position, rotation and scale defined below.
  /// So when the transform is set, the receiver's position, rotation and scale are changed to match the new transform.
  Matrix4 get transform => transformNotifier.value;

  set transform(Matrix4 matrix) {
    transformNotifier.value = matrix;
  }

  /// Determines the receiver's position.
  Vector3 get position => transform.getTranslation();

  set position(Vector3 value) {
    final old = Matrix4.fromFloat64List(transform.storage);
    final newT = old.clone();
    newT.setTranslation(value);
    transform = newT;
  }

  /// Determines the receiver's scale.
  Vector3 get scale => transform.matrixScale;

  set scale(Vector3 value) {
    transform =
        Matrix4.compose(position, Quaternion.fromRotation(rotation), value);
  }

  /// Determines the receiver's rotation.
  Matrix3 get rotation => transform.getRotation();

  set rotation(Matrix3 value) {
    transform =
        Matrix4.compose(position, Quaternion.fromRotation(value), scale);
  }

  set rotationFromQuaternion(Quaternion value) {
    transform = Matrix4.compose(position, value, scale);
  }

  /// Determines the receiver's euler angles.
  /// The order of components in this vector matches the axes of rotation:
  /// 1. Pitch (the x component) is the rotation about the node's x-axis (in radians)
  /// 2. Yaw   (the y component) is the rotation about the node's y-axis (in radians)
  /// 3. Roll  (the z component) is the rotation about the node's z-axis (in radians)
  Vector3 get eulerAngles => transform.matrixEulerAngles;

  set eulerAngles(Vector3 value) {
    final old = Matrix4.fromFloat64List(transform.storage);
    final newT = old.clone();
    newT.matrixEulerAngles = value;
    transform = newT;
  }

  final ValueNotifier<Matrix4> transformNotifier;

  /// Determines the name of the receiver.
  /// Will be autogenerated if not defined.
  final String name;

  /// Holds any data attached to the node, especially useful when uploading serialized nodes to the cloud. This data is not shared with the underlying platform
  Map<String, dynamic>? data;
  Map<String, dynamic>? asset;

  static const _matrixValueNotifierConverter = MatrixValueNotifierConverter();

  Map<String, dynamic> toMap() => <String, dynamic>{
        'uri': uri,
        'transformation':
            _matrixValueNotifierConverter.toJson(transformNotifier),
        'name': name,
        'data': data,
        'asset': asset,
      }..removeWhere((String k, dynamic v) => v == null);

  static ARNode fromMap(Map<String, dynamic> map) {
    return ARNode(
        name: map["name"] as String,
        transformation: MatrixConverter().fromJson(map["transformation"]),
        asset: Map<String, dynamic>.from(map["asset"]),
        data: Map<String, dynamic>.from(map["data"]));
  }
}

/// Helper function to create a Matrix4 from either a given matrix or from position, scale and rotation relative to the origin
Matrix4 createTransformMatrix(Matrix4? origin, Vector3? position,
    Vector3? scale, Vector4? rotation, Vector3? eulerAngles) {
  final transform = origin ?? Matrix4.identity();

  if (position != null) {
    transform.setTranslation(position);
  }
  if (rotation != null) {
    transform.rotate(
        Vector3(rotation[0], rotation[1], rotation[2]), rotation[3]);
  }
  if (eulerAngles != null) {
    transform.matrixEulerAngles = eulerAngles;
  }
  if (scale != null) {
    transform.scale(scale);
  } else {
    transform.scale(1.0);
  }
  return transform;
}

extension Matrix4Extenstion on Matrix4 {
  Vector3 get matrixScale {
    final scale = Vector3.zero();
    decompose(Vector3.zero(), Quaternion(0, 0, 0, 0), scale);
    return scale;
  }

  Vector3 get matrixEulerAngles {
    final q = Quaternion(0, 0, 0, 0);
    decompose(Vector3.zero(), q, Vector3.zero());

    final t = q.x;
    q.x = q.y;
    q.y = t;

    final angles = Vector3.zero();

    // roll (x-axis rotation)
    final sinrCosp = 2 * (q.w * q.x + q.y * q.z);
    final cosrCosp = 1 - 2 * (q.x * q.x + q.y * q.y);
    angles[0] = math.atan2(sinrCosp, cosrCosp);

    // pitch (y-axis rotation)
    final sinp = 2 * (q.w * q.y - q.z * q.x);
    if (sinp.abs() >= 1) {
      angles[1] =
          _copySign(math.pi / 2, sinp); // use 90 degrees if out of range
    } else {
      angles[1] = math.asin(sinp);
    }
    // yaw (z-axis rotation)
    final sinyCosp = 2 * (q.w * q.z + q.x * q.y);
    final cosyCosp = 1 - 2 * (q.y * q.y + q.z * q.z);
    angles[2] = math.atan2(sinyCosp, cosyCosp);

    return angles;
  }

  set matrixEulerAngles(Vector3 angles) {
    final translation = Vector3.zero();
    final scale = Vector3.zero();
    decompose(translation, Quaternion(0, 0, 0, 0), scale);
    final r = Quaternion.euler(angles[0], angles[1], angles[2]);
    setFromTranslationRotationScale(translation, r, scale);
  }
}

// https://scidart.org/docs/scidart/numdart/copySign.html
double _copySign(double magnitude, double sign) {
  // The highest order bit is going to be zero if the
  // highest order bit of m and s is the same and one otherwise.
  // So (m^s) will be positive if both m and s have the same sign
  // and negative otherwise.
  /*final long m = Double.doubleToRawLongBits(magnitude); // don't care about NaN
  final long s = Double.doubleToRawLongBits(sign);
  if ((m^s) >= 0) {
      return magnitude;
  }
  return -magnitude; // flip sign*/
  if (sign == 0.0 || sign.isNaN || magnitude.sign == sign.sign) {
    return magnitude;
  }
  return -magnitude; // flip sign
}

class MatrixValueNotifierConverter
    implements JsonConverter<ValueNotifier<Matrix4>, List<dynamic>> {
  const MatrixValueNotifierConverter();

  @override
  ValueNotifier<Matrix4> fromJson(List<dynamic> json) {
    return ValueNotifier(Matrix4.fromList(json.cast<double>()));
  }

  @override
  List<dynamic> toJson(ValueNotifier<Matrix4> matrix) {
    final list = List<double>.filled(16, 0.0);
    matrix.value.copyIntoArray(list);
    return list;
  }
}
