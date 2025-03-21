class DataPoint {
  String? id;
  int? type;
  Location? location;
  String? createdAt;
  String? updatedAt;

  DataPoint(
      {this.id, this.type, this.location, this.createdAt, this.updatedAt});

  DataPoint.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    type = json['type'];
    location = json['location'] != null
        ? new Location.fromJson(json['location'])
        : null;
    createdAt = json['createdAt'];
    updatedAt = json['updatedAt'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['type'] = type;
    if (location != null) {
      data['location'] = location!.toJson();
    }
    data['createdAt'] = createdAt;
    data['updatedAt'] = updatedAt;
    return data;
  }
}

class Location {
  double? lat;
  double? lng;

  Location({this.lat, this.lng});

  Location.fromJson(Map<String, dynamic> json) {
    lat = json['lat'];
    lng = json['lng'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['lat'] = lat;
    data['lng'] = lng;
    return data;
  }
}
