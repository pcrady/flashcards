import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/claude_service.dart';
import '../services/llm_service.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _modelController = TextEditingController();
  final _keyController = TextEditingController();
  final _baseUrlController = TextEditingController();

  SharedPreferences? _prefs;
  String _providerId = 'anthropic';
  bool _obscureKey = true;
  bool _saved = false;

  LlmProvider get _provider => LlmService.providerById(_providerId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _providerId = prefs.getString(LlmService.providerPref) ?? 'anthropic';
    _loadProviderFields();
    if (mounted) setState(() {});
  }

  /// Fills the model / key / URL fields from the stored values for the
  /// currently selected provider.
  void _loadProviderFields() {
    final prefs = _prefs;
    if (prefs == null) return;
    _modelController.text =
        prefs.getString(LlmService.modelPref(_providerId)) ??
            _provider.defaultModel;
    _keyController.text =
        prefs.getString(LlmService.keyPref(_providerId)) ?? '';
    _baseUrlController.text = prefs.getString(LlmService.customBaseUrlPref) ??
        LlmService.defaultCustomBaseUrl;
  }

  Future<void> _save() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(LlmService.providerPref, _providerId);
    await prefs.setString(
        LlmService.modelPref(_providerId), _modelController.text.trim());
    await prefs.setString(
        LlmService.keyPref(_providerId), _keyController.text.trim());
    if (_providerId == 'custom') {
      await prefs.setString(
          LlmService.customBaseUrlPref, _baseUrlController.text.trim());
    }
    setState(() => _saved = true);
  }

  @override
  void dispose() {
    _modelController.dispose();
    _keyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_saved) setState(() => _saved = false);
  }

  bool _loadingModels = false;

  Future<void> _browseModels() async {
    setState(() => _loadingModels = true);
    List<String> models;
    try {
      models = await LlmService.listModels(
        providerId: _providerId,
        apiKey: _keyController.text,
        baseUrl: _baseUrlController.text,
      );
    } on LlmException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
    if (!mounted) return;
    if (models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The provider returned no models.')),
      );
      return;
    }
    models.sort();

    final picked = await showDialog<String>(
      context: context,
      builder: (context) => _ModelPickerDialog(models: models),
    );
    if (picked != null) {
      _modelController.text = picked;
      _markDirty();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Appearance',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text(
                            SprakTheme.skin.value.blurb,
                            style: TextStyle(
                                color: SprakTheme.inkSoft, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          SegmentedButton<SprakSkin>(
                            segments: [
                              for (final s in SprakSkin.values)
                                ButtonSegment(
                                  value: s,
                                  label: Text(s.label),
                                  icon: Icon(s == SprakSkin.hacker
                                      ? Icons.terminal
                                      : Icons.auto_awesome_outlined),
                                ),
                            ],
                            selected: {SprakTheme.skin.value},
                            onSelectionChanged: (v) =>
                                SprakTheme.setSkin(v.first),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI provider',
                              style:
                                  Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text(
                            'Used for automatic card translation and the '
                            'tutor chat on the Learn screen. "Custom" works '
                            'with any OpenAI-compatible endpoint — Ollama, '
                            'LM Studio, OpenRouter, Groq…',
                            style: TextStyle(
                                color: SprakTheme.inkSoft, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _providerId,
                            decoration:
                                const InputDecoration(labelText: 'Provider'),
                            items: [
                              for (final p in kLlmProviders)
                                DropdownMenuItem(
                                    value: p.id, child: Text(p.label)),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _providerId = v;
                                _loadProviderFields();
                                _saved = false;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _modelController,
                            decoration: InputDecoration(
                              labelText: 'Model',
                              hintText: _provider.defaultModel,
                              suffixIcon: _loadingModels
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(
                                          Icons.manage_search, size: 22),
                                      tooltip:
                                          'Browse available models',
                                      onPressed: _browseModels,
                                    ),
                            ),
                            onChanged: (_) => _markDirty(),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed:
                                  _loadingModels ? null : _browseModels,
                              child: const Text(
                                  'Browse available models…'),
                            ),
                          ),
                          if (_providerId == 'custom') ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _baseUrlController,
                              decoration: const InputDecoration(
                                labelText: 'Base URL',
                                hintText: LlmService.defaultCustomBaseUrl,
                              ),
                              onChanged: (_) => _markDirty(),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: _keyController,
                            obscureText: _obscureKey,
                            decoration: InputDecoration(
                              labelText: '${_provider.label} API key'
                                  '${_provider.keyRequired ? "" : " (optional)"}',
                              hintText: _providerId == 'anthropic'
                                  ? 'sk-ant-…'
                                  : null,
                              suffixIcon: IconButton(
                                icon: Icon(_obscureKey
                                    ? Icons.visibility
                                    : Icons.visibility_off),
                                onPressed: () => setState(
                                    () => _obscureKey = !_obscureKey),
                              ),
                            ),
                            onChanged: (_) => _markDirty(),
                          ),
                          if (_providerId == 'anthropic') ...[
                            const SizedBox(height: 8),
                            Text(
                              'If left empty, the ANTHROPIC_API_KEY '
                              'environment variable is used instead.',
                              style: TextStyle(
                                  color: SprakTheme.inkSoft, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _save,
                        child: const Text('Save'),
                      ),
                      if (_saved)
                        const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Text('Saved ✓'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Searchable list of model IDs returned by the provider.
class _ModelPickerDialog extends StatefulWidget {
  final List<String> models;
  const _ModelPickerDialog({required this.models});

  @override
  State<_ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<_ModelPickerDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filtered = [
      for (final m in widget.models)
        if (m.toLowerCase().contains(_filter.toLowerCase())) m,
    ];
    return AlertDialog(
      title: const Text('Choose a model'),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Filter…',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('No models match.',
                          style: TextStyle(color: SprakTheme.inkSoft)),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        title: Text(filtered[i]),
                        onTap: () =>
                            Navigator.pop(context, filtered[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
