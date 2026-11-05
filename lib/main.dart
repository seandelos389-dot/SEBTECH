import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';

String normalizeProductCategory(Object? value) {
  final category = value?.toString().trim().toLowerCase() ?? '';

  if (category.isEmpty || category == 'uncategorized' || category == 'other') {
    return 'Other';
  }
  if (['laptop', 'laptops', 'notebook', 'notebooks'].contains(category)) {
    return 'Laptop';
  }
  if (['gpu', 'gpus', 'graphics card', 'graphics cards'].contains(category)) {
    return 'GPU';
  }
  if (['cpu', 'cpus', 'processor', 'processors'].contains(category)) {
    return 'CPU';
  }
  if (['storage', 'ssd', 'hdd', 'drive', 'drives'].contains(category)) {
    return 'Storage';
  }
  if ([
    'accessory',
    'accessories',
    'peripheral',
    'peripherals',
  ].contains(category)) {
    return 'Accessories';
  }
  return 'Other';
}

bool productMatchesSearch(Map<dynamic, dynamic> product, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return true;

  final searchableText = [
    product['name'],
    product['category'],
    product['price'],
    product['stock'],
  ].whereType<Object>().join(' ').toLowerCase();

  return normalizedQuery.split(RegExp(r'\s+')).every(searchableText.contains);
}

Widget productImageWidget(String image, IconData fallbackIcon) {
  final trimmedImage = image.trim();
  final uri = Uri.tryParse(trimmedImage);
  final isRemoteImage =
      uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  final fallback = Icon(fallbackIcon, color: Colors.blue, size: 32);

  if (trimmedImage.isEmpty) return fallback;
  if (trimmedImage.toLowerCase().startsWith('data:image/')) {
    final dataUrl = RegExp(
      r'^data:image/[^,]*;base64,',
      caseSensitive: false,
    ).firstMatch(trimmedImage);
    if (dataUrl == null) {
      debugPrint('Product image data URL is missing its base64 encoding.');
      return fallback;
    }
    try {
      return Image.memory(
        base64Decode(trimmedImage.substring(dataUrl.end)),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Could not decode product image: $error');
          return fallback;
        },
      );
    } on FormatException {
      debugPrint('Product image contains invalid base64 data.');
      return fallback;
    }
  }
  if (isRemoteImage) {
    return Image.network(
      trimmedImage,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
  return Image.asset(
    'assets/products/$trimmedImage',
    fit: BoxFit.contain,
    errorBuilder: (context, error, stackTrace) => fallback,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SEBTECH Store',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080B10),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.hasError) {
          return _authErrorPage(
            'Unable to check your sign-in: ${authSnapshot.error}',
          );
        }

        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnapshot.data;
        if (user == null) return const LoginPage();

        return HomePage(
          userId: user.uid,
          username:
              user.displayName ?? user.email?.split('@').first ?? 'Customer',
        );
      },
    );
  }

  Widget _authErrorPage(String message) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Colors.redAccent, size: 38),
              const SizedBox(height: 12),
              const Text(
                'Account connection failed',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;
  bool hidePassword = true;
  bool isCreatingAccount = false;

  Future<void> _submit() async {
    final username = usernameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (isCreatingAccount && username.isEmpty) {
      _showMessage('Username cannot be empty');
      return;
    }

    if (email.isEmpty || !email.contains('@')) {
      _showMessage('Enter a valid email address');
      return;
    }

    if (password.isEmpty) {
      _showMessage('Password cannot be empty');
      return;
    }

    if (isCreatingAccount && password.length < 6) {
      _showMessage('Password must be at least 6 characters');
      return;
    }

    if (isCreatingAccount && password != confirmPasswordController.text) {
      _showMessage('Passwords do not match');
      return;
    }

    setState(() => isLoading = true);

    try {
      if (isCreatingAccount) {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        await credential.user!.updateDisplayName(username);
        await FirebaseDatabase.instance
            .ref('profiles/${credential.user!.uid}')
            .set({
              'username': username,
              'email': email,
              'createdAt': ServerValue.timestamp,
            });
      } else {
        final credential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        final user = credential.user!;
        final profileRef = FirebaseDatabase.instance.ref(
          'profiles/${user.uid}',
        );
        final profile = await profileRef.get();
        if (!profile.exists) {
          await profileRef.set({
            'username': user.displayName ?? email.split('@').first,
            'email': user.email ?? email,
            'createdAt': ServerValue.timestamp,
          });
        }
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      _showMessage(_authErrorMessage(error));
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        'Unable to ${isCreatingAccount ? 'create account' : 'sign in'}: $error',
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _authErrorMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'email-already-in-use' => 'An account already uses this email.',
      'invalid-email' => 'Enter a valid email address.',
      'weak-password' =>
        'Choose a stronger password with at least 6 characters.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'The email or password is incorrect.',
      'network-request-failed' =>
        'Check your internet connection and try again.',
      'operation-not-allowed' =>
        'Enable Email/Password sign-in in Firebase Authentication.',
      _ => error.message ?? 'Authentication failed (${error.code}).',
    };
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF10151D),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.computer_rounded,
                        color: Colors.blue,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'SEBTECH',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Technology Store',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 22),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        isCreatingAccount
                            ? 'Create your account'
                            : 'Welcome back',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        isCreatingAccount
                            ? 'Set up your account to start shopping.'
                            : 'Sign in to continue.',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (isCreatingAccount) ...[
                      TextField(
                        controller: usernameController,
                        textInputAction: TextInputAction.next,
                        decoration: _authInputDecoration(
                          'Username',
                          Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 11),
                    ],
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _authInputDecoration(
                        'Email',
                        Icons.email_outlined,
                      ),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: passwordController,
                      obscureText: hidePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!isLoading) _submit();
                      },
                      decoration:
                          _authInputDecoration(
                            'Password',
                            Icons.lock_outline,
                          ).copyWith(
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() => hidePassword = !hidePassword);
                              },
                              icon: Icon(
                                hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                    ),
                    if (isCreatingAccount) ...[
                      const SizedBox(height: 11),
                      TextField(
                        controller: confirmPasswordController,
                        obscureText: hidePassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!isLoading) _submit();
                        },
                        decoration: _authInputDecoration(
                          'Confirm password',
                          Icons.lock_outline,
                        ),
                      ),
                    ],
                    const SizedBox(height: 17),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 19,
                                width: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isCreatingAccount ? 'CREATE ACCOUNT' : 'LOGIN',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () => setState(() {
                              isCreatingAccount = !isCreatingAccount;
                            }),
                      child: Text(
                        isCreatingAccount
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _authInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: const Color(0xFF151A22),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide.none,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String userId;
  final String username;

  const HomePage({super.key, required this.userId, required this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedIndex = 0;

  final DatabaseReference productsRef = FirebaseDatabase.instance.ref(
    'products',
  );

  final DatabaseReference cartRef = FirebaseDatabase.instance.ref('cart');

  final DatabaseReference transactionsRef = FirebaseDatabase.instance.ref(
    'transactions',
  );

  String searchText = '';
  String selectedCategory = 'All';
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _addToCart(
    String productId,
    Map<dynamic, dynamic> product,
  ) async {
    final name = product['name']?.toString() ?? 'Product';
    final price = double.tryParse(product['price']?.toString() ?? '0') ?? 0;

    final userCartRef = cartRef.child(widget.userId).child(productId);

    final existing = await userCartRef.get();

    int quantity = 1;

    if (existing.exists && existing.value is Map) {
      final existingData = Map<dynamic, dynamic>.from(existing.value as Map);

      quantity =
          (int.tryParse(existingData['quantity']?.toString() ?? '0') ?? 0) + 1;
    }

    await userCartRef.set({
      'productId': productId,
      'name': name,
      'price': price,
      'quantity': quantity,
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name added to cart'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _logout() {
    FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _homeContent(),
      CartPage(
        userId: widget.userId,
        username: widget.username,
        cartRef: cartRef,
        productsRef: productsRef,
        transactionsRef: transactionsRef,
      ),
      OrdersPage(
        userId: widget.userId,
        username: widget.username,
        transactionsRef: transactionsRef,
      ),
      _profilePage(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[selectedIndex]),

      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        backgroundColor: const Color(0xFF0D1117),
        indicatorColor: Colors.blue.withValues(alpha: 0.25),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart),
            label: 'Cart',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // HOME CONTENT
  // ==========================================================

  Widget _homeContent() {
    return StreamBuilder<DatabaseEvent>(
      stream: productsRef.onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Unable to load products. Check Firebase Realtime Database '
                    'Rules and allow authenticated users to read /products.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data?.snapshot.value;

        Map<dynamic, dynamic> products = {};

        if (data != null && data is Map) {
          products = Map<dynamic, dynamic>.from(data);
        }

        final filteredProducts = products.entries.where((entry) {
          final product = Map<dynamic, dynamic>.from(entry.value as Map);

          final category = normalizeProductCategory(product['category']);
          final matchesSearch = productMatchesSearch(product, searchText);

          final matchesCategory =
              selectedCategory == 'All' || category == selectedCategory;

          return matchesSearch && matchesCategory;
        }).toList();

        return SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // TOP BAR
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SEBTECH',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),

                        IconButton(
                          onPressed: () {
                            setState(() {
                              selectedIndex = 2;
                            });
                          },
                          icon: const Icon(Icons.shopping_cart_outlined),
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),

                    // SEARCH
                    TextField(
                      controller: searchController,
                      onChanged: (value) {
                        setState(() {
                          searchText = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search products...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchText.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  searchController.clear();
                                  setState(() {
                                    searchText = '';
                                  });
                                },
                                icon: const Icon(Icons.close),
                              ),
                        filled: true,
                        fillColor: const Color(0xFF151A22),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // STORE BANNER
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0066FF), Color(0xFF003FA8)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SEBTECH STORE',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Your trusted tech store',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    const Text(
                      'Categories',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 12),

                    _categoryRow(),

                    const SizedBox(height: 25),

                    const Text(
                      'Featured Products',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (filteredProducts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(30),
                        child: Center(
                          child: Text(
                            searchText.trim().isNotEmpty
                                ? 'No products match your search'
                                : selectedCategory != 'All'
                                ? 'No products in this category'
                                : 'No products found',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredProducts.length,
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 280,
                                  mainAxisExtent: constraints.maxWidth < 380
                                      ? 350
                                      : 320,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 14,
                                ),
                            itemBuilder: (context, index) {
                              final entry = filteredProducts[index];
                              final productId = entry.key.toString();
                              final product = Map<dynamic, dynamic>.from(
                                entry.value as Map,
                              );

                              return _productCard(productId, product);
                            },
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // CATEGORY ROW
  // ==========================================================

  Widget _categoryRow() {
    final categories = [
      {'name': 'All', 'icon': Icons.apps},
      {'name': 'Laptop', 'icon': Icons.laptop},
      {'name': 'GPU', 'icon': Icons.memory},
      {'name': 'CPU', 'icon': Icons.developer_board},
      {'name': 'Storage', 'icon': Icons.storage},
      {'name': 'Accessories', 'icon': Icons.devices_other},
      {'name': 'Other', 'icon': Icons.category},
    ];

    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final category = categories[index];
          final name = category['name'] as String;
          final icon = category['icon'] as IconData;

          final selected = selectedCategory == name;

          return GestureDetector(
            onTap: () {
              setState(() {
                selectedCategory = name;
              });
            },
            child: Container(
              width: 78,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.blue.withValues(alpha: 0.2)
                    : const Color(0xFF151A22),
                borderRadius: BorderRadius.circular(12),
                border: selected ? Border.all(color: Colors.blue) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.blue, size: 25),
                  const SizedBox(height: 7),
                  Text(name, style: const TextStyle(fontSize: 10)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ==========================================================
  // PRODUCT CARD
  // ==========================================================

  Widget _productCard(String productId, Map<dynamic, dynamic> product) {
    final name = product['name']?.toString() ?? 'Product';
    final category = normalizeProductCategory(product['category']);
    final imageName = product['image']?.toString().trim() ?? '';
    final price = double.tryParse(product['price']?.toString() ?? '0') ?? 0;
    final stock = int.tryParse(product['stock']?.toString() ?? '0') ?? 0;

    IconData icon = Icons.memory;
    if (category == 'Storage') {
      icon = Icons.storage;
    } else if (category == 'Laptop') {
      icon = Icons.laptop;
    } else if (category == 'CPU') {
      icon = Icons.developer_board;
    } else if (category == 'Accessories') {
      icon = Icons.devices_other;
    } else if (category == 'Other') {
      icon = Icons.category;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF151A22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: const Color(0xFF202733),
                  padding: const EdgeInsets.all(10),
                  child: productImageWidget(imageName, icon),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 3),
          Text(
            category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            '₱${price.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: stock <= 0
                  ? null
                  : () => _addToCart(productId, product),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: Colors.blue,
                disabledBackgroundColor: Colors.white10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                stock <= 0 ? 'Out of Stock' : 'Add to Cart',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // PROFILE
  // ==========================================================

  Widget _profilePage() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Profile',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 25),

        Center(
          child: CircleAvatar(
            radius: 42,
            backgroundColor: Colors.blue.withValues(alpha: 0.2),
            child: const Icon(Icons.person, size: 45, color: Colors.blue),
          ),
        ),

        const SizedBox(height: 15),

        Center(
          child: Text(
            widget.username,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),

        const SizedBox(height: 35),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF151A22),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Row(
            children: [
              Icon(Icons.verified_user_outlined, color: Colors.blue),
              SizedBox(width: 12),
              Text('Logged in successfully'),
            ],
          ),
        ),

        const SizedBox(height: 20),

        ElevatedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: const Text('Logout'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
        ),
      ],
    );
  }
}

class CartPage extends StatefulWidget {
  final String userId;
  final String username;
  final DatabaseReference cartRef;
  final DatabaseReference productsRef;
  final DatabaseReference transactionsRef;

  const CartPage({
    super.key,
    required this.userId,
    required this.username,
    required this.cartRef,
    required this.productsRef,
    required this.transactionsRef,
  });

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  double _calculateTotal(Map<dynamic, dynamic> cart) {
    double total = 0;

    for (final entry in cart.entries) {
      final item = Map<dynamic, dynamic>.from(entry.value as Map);

      final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;

      final quantity = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;

      total += price * quantity;
    }

    return total;
  }

  Future<void> _changeQuantity(
    String productId,
    Map<dynamic, dynamic> item,
    int change,
  ) async {
    final current = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;

    final newQuantity = current + change;

    final itemRef = widget.cartRef.child(widget.userId).child(productId);

    if (newQuantity <= 0) {
      await itemRef.remove();
    } else {
      await itemRef.update({'quantity': newQuantity});
    }
  }

  Future<void> _checkout(Map<dynamic, dynamic> cart) async {
    if (cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Your cart is empty')));
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutPage(
          userId: widget.userId,
          username: widget.username,
          cart: cart,
          total: _calculateTotal(cart),
          cartRef: widget.cartRef,
          transactionsRef: widget.transactionsRef,
        ),
      ),
    );

    if (result == true) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final userCartRef = widget.cartRef.child(widget.userId);

    return StreamBuilder<DatabaseEvent>(
      stream: userCartRef.onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Unable to load cart: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data?.snapshot.value;

        Map<dynamic, dynamic> cart = {};

        if (data != null && data is Map) {
          cart = Map<dynamic, dynamic>.from(data);
        }

        final total = _calculateTotal(cart);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                children: [
                  const Text(
                    'Your Cart',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '${cart.length} items',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),

            Expanded(
              child: cart.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 65,
                            color: Colors.white24,
                          ),
                          SizedBox(height: 15),
                          Text(
                            'Your cart is empty',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ...cart.entries.map((entry) {
                          final productId = entry.key.toString();

                          final item = Map<dynamic, dynamic>.from(
                            entry.value as Map,
                          );

                          final name = item['name']?.toString() ?? 'Product';

                          final price =
                              double.tryParse(
                                item['price']?.toString() ?? '0',
                              ) ??
                              0;

                          final quantity =
                              int.tryParse(
                                item['quantity']?.toString() ?? '1',
                              ) ??
                              1;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF151A22),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    color: const Color(0xFF202733),
                                    padding: const EdgeInsets.all(5),
                                    child: StreamBuilder<DatabaseEvent>(
                                      stream: widget.productsRef
                                          .child(productId)
                                          .child('image')
                                          .onValue,
                                      builder: (context, imageSnapshot) {
                                        final image =
                                            imageSnapshot.data?.snapshot.value
                                                ?.toString() ??
                                            '';
                                        return productImageWidget(
                                          image,
                                          Icons.memory,
                                        );
                                      },
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '₱${price.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: Colors.blue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                IconButton(
                                  onPressed: () {
                                    _changeQuantity(productId, item, -1);
                                  },
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),

                                Text(
                                  '$quantity',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                IconButton(
                                  onPressed: () {
                                    _changeQuantity(productId, item, 1);
                                  },
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
            ),

            if (cart.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 15, 20, 20),
                decoration: const BoxDecoration(color: Color(0xFF0D1117)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('Total', style: TextStyle(fontSize: 16)),
                        const Spacer(),
                        Text(
                          '₱${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          _checkout(cart);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                        ),
                        child: const Text(
                          'CHECKOUT',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class CheckoutPage extends StatefulWidget {
  final String userId;
  final String username;
  final Map<dynamic, dynamic> cart;
  final double total;
  final DatabaseReference cartRef;
  final DatabaseReference transactionsRef;

  const CheckoutPage({
    super.key,
    required this.userId,
    required this.username,
    required this.cart,
    required this.total,
    required this.cartRef,
    required this.transactionsRef,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final nameController = TextEditingController();

  final addressController = TextEditingController();

  String? paymentMethod;

  bool isProcessing = false;

  Future<void> _placeOrder() async {
    final name = nameController.text.trim();

    final address = addressController.text.trim();

    if (name.isEmpty) {
      _showMessage('Please enter customer name');
      return;
    }

    if (address.isEmpty) {
      _showMessage('Please enter address');
      return;
    }

    if (paymentMethod == null) {
      _showMessage('Please select payment method');
      return;
    }

    setState(() {
      isProcessing = true;
    });

    try {
      final transaction = widget.transactionsRef.child(widget.userId).push();

      final items = <Map<String, dynamic>>[];

      for (final entry in widget.cart.entries) {
        final item = Map<dynamic, dynamic>.from(entry.value as Map);

        items.add({
          'productId': item['productId']?.toString(),
          'name': item['name']?.toString(),
          'price': double.tryParse(item['price']?.toString() ?? '0') ?? 0,
          'quantity': int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
        });
      }

      await transaction.set({
        'username': widget.username,
        'customerName': name,
        'address': address,
        'paymentMethod': paymentMethod,
        'total': widget.total,
        'items': items,
        'date': DateTime.now().toIso8601String(),
        'status': 'Completed',
      });

      // Clear cart
      await widget.cartRef.child(widget.userId).remove();

      if (!mounted) return;

      setState(() {
        isProcessing = false;
      });

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF151A22),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 10),
                Text('Success'),
              ],
            ),
            content: const Text('Your transaction was completed successfully.'),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isProcessing = false;
      });

      _showMessage('Transaction failed: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    nameController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: const Color(0xFF080B10),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Customer Information',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 18),

            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Customer Name',
                prefixIcon: const Icon(Icons.person_outline),
                filled: true,
                fillColor: const Color(0xFF151A22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: addressController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Address',
                prefixIcon: const Icon(Icons.location_on_outlined),
                filled: true,
                fillColor: const Color(0xFF151A22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 15),

            DropdownButtonFormField<String>(
              initialValue: paymentMethod,
              decoration: InputDecoration(
                labelText: 'Payment Method',
                prefixIcon: const Icon(Icons.payment),
                filled: true,
                fillColor: const Color(0xFF151A22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                DropdownMenuItem(value: 'GCash', child: Text('GCash')),
                DropdownMenuItem(
                  value: 'Bank Transfer',
                  child: Text('Bank Transfer'),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  paymentMethod = value;
                });
              },
            ),

            const SizedBox(height: 30),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF151A22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Text('Total', style: TextStyle(fontSize: 17)),
                  const Spacer(),
                  Text(
                    '₱${widget.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isProcessing ? null : _placeOrder,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: isProcessing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'PLACE ORDER',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OrdersPage extends StatelessWidget {
  final String userId;
  final String username;
  final DatabaseReference transactionsRef;

  const OrdersPage({
    super.key,
    required this.userId,
    required this.username,
    required this.transactionsRef,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: transactionsRef.child(userId).onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Unable to load orders: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data?.snapshot.value;

        Map<dynamic, dynamic> transactions = {};

        if (data != null && data is Map) {
          transactions = Map<dynamic, dynamic>.from(data);
        }

        final userTransactions = transactions.entries.toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Text(
                'My Orders',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
              ),
            ),

            Expanded(
              child: userTransactions.isEmpty
                  ? const Center(
                      child: Text(
                        'No transactions yet',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: userTransactions.length,
                      itemBuilder: (context, index) {
                        final entry =
                            userTransactions[userTransactions.length -
                                1 -
                                index];

                        final transaction = Map<dynamic, dynamic>.from(
                          entry.value as Map,
                        );

                        final total =
                            double.tryParse(
                              transaction['total']?.toString() ?? '0',
                            ) ??
                            0;

                        final date = transaction['date']?.toString() ?? '';

                        final status =
                            transaction['status']?.toString() ?? 'Completed';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF151A22),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.receipt_long,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Transaction ${index + 1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    status,
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              Text(
                                'Customer: ${transaction['customerName'] ?? ''}',
                              ),

                              const SizedBox(height: 5),

                              Text(
                                'Payment: ${transaction['paymentMethod'] ?? ''}',
                                style: const TextStyle(color: Colors.white54),
                              ),

                              const SizedBox(height: 5),

                              Text(
                                'Date: $date',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),

                              const SizedBox(height: 10),

                              Text(
                                '₱${total.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final rootRef = FirebaseDatabase.instance.ref();

    return Scaffold(
      backgroundColor: const Color(0xFF080B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10151D),
        title: const Text(
          'SEBTECH Web Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: rootRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load dashboard data: ${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }

          final raw = snapshot.data?.snapshot.value;
          final root = raw is Map
              ? Map<dynamic, dynamic>.from(raw)
              : <dynamic, dynamic>{};

          final products = root['products'] is Map
              ? Map<dynamic, dynamic>.from(root['products'] as Map)
              : <dynamic, dynamic>{};
          final users = root['users'] is Map
              ? Map<dynamic, dynamic>.from(root['users'] as Map)
              : <dynamic, dynamic>{};
          final transactions = root['transactions'] is Map
              ? Map<dynamic, dynamic>.from(root['transactions'] as Map)
              : <dynamic, dynamic>{};

          double totalSales = 0;
          for (final entry in transactions.entries) {
            if (entry.value is Map) {
              final tx = Map<dynamic, dynamic>.from(entry.value as Map);
              totalSales +=
                  double.tryParse(tx['total']?.toString() ?? '0') ?? 0;
            }
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 800;
              final contentWidth = isWide ? 1150.0 : double.infinity;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Dashboard',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Overview of your SEBTECH store',
                          style: TextStyle(color: Colors.white54),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _statCard(
                              'Products',
                              products.length.toString(),
                              Icons.inventory_2_outlined,
                            ),
                            _statCard(
                              'Users',
                              users.length.toString(),
                              Icons.people_outline,
                            ),
                            _statCard(
                              'Transactions',
                              transactions.length.toString(),
                              Icons.receipt_long_outlined,
                            ),
                            _statCard(
                              'Total Sales',
                              '₱${totalSales.toStringAsFixed(2)}',
                              Icons.payments_outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                        const Text(
                          'Products',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _productsTable(products),
                        const SizedBox(height: 30),
                        const Text(
                          'Recent Transactions',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _transactionsTable(transactions),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon) {
    return SizedBox(
      width: 250,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF151A22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productsTable(Map<dynamic, dynamic> products) {
    if (products.isEmpty) {
      return _emptyCard('No products found');
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151A22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: products.entries.map((entry) {
          final product = entry.value is Map
              ? Map<dynamic, dynamic>.from(entry.value as Map)
              : <dynamic, dynamic>{};
          final name = product['name']?.toString() ?? 'Product';
          final category = normalizeProductCategory(product['category']);
          final price =
              double.tryParse(product['price']?.toString() ?? '0') ?? 0;
          final stock = int.tryParse(product['stock']?.toString() ?? '0') ?? 0;
          final image = product['image']?.toString().trim() ?? '';

          return ListTile(
            leading: SizedBox(
              width: 48,
              height: 48,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: productImageWidget(image, Icons.memory),
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '$category • Stock: $stock',
              style: const TextStyle(color: Colors.white54),
            ),
            trailing: Text(
              '₱${price.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _transactionsTable(Map<dynamic, dynamic> transactions) {
    if (transactions.isEmpty) {
      return _emptyCard('No transactions found');
    }

    final entries = transactions.entries.toList().reversed.take(10).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151A22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: entries.map((entry) {
          final tx = entry.value is Map
              ? Map<dynamic, dynamic>.from(entry.value as Map)
              : <dynamic, dynamic>{};
          final customer =
              tx['customerName']?.toString() ??
              tx['username']?.toString() ??
              'Customer';
          final total = double.tryParse(tx['total']?.toString() ?? '0') ?? 0;
          final status = tx['status']?.toString() ?? 'Completed';
          final date = tx['date']?.toString() ?? '';

          return ListTile(
            leading: const Icon(Icons.receipt_long, color: Colors.blue),
            title: Text(
              customer,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              date.isEmpty ? status : '$date • $status',
              style: const TextStyle(color: Colors.white54),
            ),
            trailing: Text(
              '₱${total.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: const Color(0xFF151A22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(text, style: const TextStyle(color: Colors.white54)),
      ),
    );
  }
}
