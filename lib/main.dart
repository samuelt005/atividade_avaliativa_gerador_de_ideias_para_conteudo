import 'dart:convert'; // Import for jsonDecode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for Clipboard
import 'package:google_generative_ai/google_generative_ai.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gerador de Ideias de Conteúdo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.white,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const HomePage(title: 'Gerador de Ideias de Conteúdo'),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();

  bool _isLoading = false;
  List<Map<String, dynamic>> _generatedIdeas = []; // Store parsed ideas
  String? _errorMessage;
  GenerativeModel? _model;

  // --- Helper function to build the text for copying ---
  String _buildCopyText(Map<String, dynamic> idea) {
    final title = idea['titulo'] ?? 'Sem Título';
    final audience = idea['publico_alvo'] ?? 'Não especificado';
    final outline = (idea['esboco'] as List<dynamic>?)?.cast<String>() ?? [];

    final outlineString = outline.map((item) => "- $item").join('\n');

    return '''
**Título:** $title

**Público-Alvo:** $audience

**Esboço:**
$outlineString
''';
  }

  Future<void> _generateContentIdeas() async {
    // --- Input Validations (unchanged) ---
    if (_apiKeyController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Por favor, insira sua Chave de API do Google AI.';
        _generatedIdeas = [];
      });
      return;
    }
    if (_topicController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Por favor, descreva o nicho ou tema desejado.';
        _generatedIdeas = [];
      });
      return;
    }
    // --- ---

    setState(() {
      _isLoading = true;
      _generatedIdeas = []; // Clear previous ideas
      _errorMessage = null;
    });

    try {
      // --- Initialize Model (mostly unchanged) ---
      _model = GenerativeModel(
        model: 'gemini-1.5-flash-latest',
        apiKey: _apiKeyController.text.trim(),
        generationConfig: GenerationConfig(
          temperature: 0.7, // Slightly lower temp for more structured JSON
          // Ensure response mimetype is explicitly set if needed,
          // though usually handled by the prompt itself for Gemini.
        ),
      );
      // --- ---

      // --- *** MODIFIED PROMPT FOR JSON *** ---
      final prompt = '''
      Aja como um especialista em criação de conteúdo digital.
      Gere 3 ideias de conteúdo (para blog ou rede social) sobre o seguinte nicho/tópico: "${_topicController.text}".

      Retorne a resposta EXCLUSIVAMENTE em formato JSON válido, como uma lista (array) de objetos.
      NÃO inclua nenhuma explicação, texto introdutório, formatação markdown ou ```json ``` antes ou depois do JSON.
      A resposta deve ser APENAS o JSON.

      Cada objeto na lista deve ter EXATAMENTE as seguintes chaves e tipos:
      - "titulo": (String) Um título chamativo e claro para a ideia.
      - "publico_alvo": (String) Descrição do público para quem este conteúdo seria mais relevante.
      - "esboco": (List<String>) Uma lista (array) com 3 a 5 strings curtas, representando os principais pontos a serem abordados no conteúdo.

      Exemplo de formato JSON esperado:
      [
        {
          "titulo": "Exemplo de Título 1",
          "publico_alvo": "Iniciantes em Flutter",
          "esboco": ["Introdução aos Widgets", "Layouts Básicos", "Gerenciamento de Estado Simples"]
        },
        {
          "titulo": "Exemplo de Título 2",
          "publico_alvo": "Empreendedores Digitais",
          "esboco": ["Funil de Vendas", "Marketing de Conteúdo", "Análise de Métricas", "SEO para Blogs"]
        }
      ]
      ''';
      // --- *** END OF MODIFIED PROMPT *** ---

      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);
      final responseText = response.text;

      if (responseText == null || responseText.isEmpty) {
        throw Exception("A API retornou uma resposta vazia.");
      }

      // --- *** PARSE JSON RESPONSE *** ---
      try {
        // Clean the response text slightly just in case (remove potential backticks)
        final cleanJsonResponse =
            responseText
                .trim()
                .replaceAll('```json', '')
                .replaceAll('```', '')
                .trim();

        final decodedJson = jsonDecode(cleanJsonResponse);

        if (decodedJson is List) {
          // Ensure it's List<Map<String, dynamic>>
          _generatedIdeas = List<Map<String, dynamic>>.from(
            decodedJson.map((item) {
              if (item is Map) {
                // Make sure nested 'esboco' is List<String>
                if (item.containsKey('esboco') && item['esboco'] is List) {
                  item['esboco'] = List<String>.from(item['esboco']);
                } else {
                  // Handle case where 'esboco' might be missing or wrong type
                  item['esboco'] = <String>[
                    'Esboço indisponível ou formato inválido',
                  ];
                }
                return Map<String, dynamic>.from(item); // Cast inner maps too
              } else {
                // Handle unexpected item type in the list
                return <String, dynamic>{
                  'titulo': 'Erro: Item inválido',
                  'publico_alvo': '',
                  'esboco': [],
                };
              }
            }),
          );
        } else {
          throw const FormatException(
            "A resposta da API não era uma lista JSON válida.",
          );
        }
      } catch (e) {
        print('Erro ao decodificar JSON: $e');
        print('Resposta recebida da API: $responseText'); // Log raw response
        throw FormatException(
          "Erro ao processar a resposta da API. Resposta não está no formato JSON esperado. Detalhes: ${e.toString()}",
        );
      }
      // --- *** END OF JSON PARSING *** ---

      setState(() {
        _isLoading = false;
        _errorMessage = null; // Clear error on success
      });
    } catch (e) {
      print('Erro ao gerar conteúdo: $e');
      setState(() {
        _errorMessage =
            'Ocorreu um erro: ${e.toString()}. Verifique sua chave de API, conexão e se a resposta da API está correta.';
        _isLoading = false;
        _generatedIdeas = []; // Clear ideas on error
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme; // Get text theme

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor:
            Theme.of(
              context,
            ).colorScheme.inversePrimary, // Added for better AppBar visibility
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // --- Input Fields (unchanged appearance) ---
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'Sua Chave de API do Google AI (Gemini)',
                hintText: 'Cole sua chave aqui',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 20.0),

            TextField(
              controller: _topicController,
              decoration: const InputDecoration(
                labelText: 'Nicho ou Tópico Principal',
                hintText: 'Ex: "Marketing de afiliados para iniciantes"',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.topic_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20.0),

            // --- ---
            ElevatedButton.icon(
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('Gerar Ideias'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                // Bolder text
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  // Rounded corners
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isLoading ? null : _generateContentIdeas,
            ),
            const SizedBox(height: 25.0),

            // --- Section Title ---
            Row(
              // Use Row for title and divider alignment
              children: [
                Text(
                  'Ideias Geradas:',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ), // Use headlineSmall
                ),
                const Expanded(child: Divider(indent: 8, thickness: 1)),
              ],
            ),
            //const Divider(), // Divider moved above or integrated
            const SizedBox(height: 10.0),

            // --- Display Area ---
            _isLoading
                ? const Center(
                  child: Padding(
                    // Add padding around indicator
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ),
                )
                : _errorMessage != null
                ? Container(
                  // Add background for error message
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
                : _generatedIdeas
                    .isEmpty // Check if the list is empty
                ? const Text(
                  'Insira seu nicho acima e clique em "Gerar Ideias" para começar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                )
                // --- *** DISPLAY CARDS *** ---
                : Column(
                  // Build Cards from the list
                  children:
                      _generatedIdeas.map((idea) {
                        final title =
                            idea['titulo']?.toString() ??
                            'Título não disponível';
                        final audience =
                            idea['publico_alvo']?.toString() ??
                            'Público não disponível';
                        final outline =
                            (idea['esboco'] as List<dynamic>?)
                                ?.map(
                                  (e) => e.toString(),
                                ) // Ensure elements are strings
                                ?.toList() ??
                            ['Esboço não disponível'];

                        final copyContent = _buildCopyText(
                          idea,
                        ); // Get text for copy button

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title
                                Text(
                                  title,
                                  style: textTheme.titleLarge?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ), // Style Title
                                ),
                                const SizedBox(height: 12),

                                // Audience
                                Text(
                                  'Público-Alvo:',
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(audience, style: textTheme.bodyMedium),
                                const SizedBox(height: 12),

                                // Outline
                                Text(
                                  'Esboço Rápido:',
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ...outline
                                    .map(
                                      (item) => Padding(
                                        padding: const EdgeInsets.only(
                                          left: 8.0,
                                          top: 2,
                                          bottom: 2,
                                        ),
                                        child: Row(
                                          // Use Row for bullet point
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              "• ",
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                item,
                                                style: textTheme.bodyMedium,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                                const SizedBox(height: 16),

                                // --- Copy Button ---
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.copy, size: 18),
                                    label: const Text('Copiar'),
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: copyContent),
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Ideia copiada para a área de transferência!',
                                          ),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      textStyle: const TextStyle(fontSize: 14),
                                      // foregroundColor: Theme.of(context).colorScheme.primary // Optional color override
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                ),
            // --- *** END OF DISPLAY CARDS *** ---
          ],
        ),
      ),
    );
  }
}
