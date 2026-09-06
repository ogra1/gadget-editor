class GadgetModel {
  final String? snapName;
  final String? gadgetContent;
  final Map<String, dynamic>? gadgetData;
  final List<Map<String, dynamic>> availableChannels;
  
  GadgetModel({
    this.snapName,
    this.gadgetContent,
    this.gadgetData,
    this.availableChannels = const [],
  });
}
