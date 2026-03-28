/**
 * Edge-to-edge and window insets — Android 15 (API 35) enforces this.
 *
 * Without inset handling, content will be drawn behind system bars
 * and clipped on API 35+ devices.
 */

import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.updatePadding

// ---- View-based activity ----------------------------------------------------

class EdgeToEdgeActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // Tell the system to let our app draw behind system bars
        WindowCompat.setDecorFitsSystemWindows(window, false)

        val rootView = findViewById<View>(R.id.root)

        // Apply system bar insets as padding so content isn't hidden
        ViewCompat.setOnApplyWindowInsetsListener(rootView) { view, windowInsets ->
            val bars = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(
                left = bars.left,
                top = bars.top,
                right = bars.right,
                bottom = bars.bottom
            )
            WindowInsetsCompat.CONSUMED
        }
    }
}

// ---- Bottom nav / FAB — only pad bottom -------------------------------------

fun applyBottomInsets(view: View) {
    ViewCompat.setOnApplyWindowInsetsListener(view) { v, windowInsets ->
        val bars = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars())
        v.updatePadding(bottom = bars.bottom)
        windowInsets
    }
}

// ---- IME (keyboard) animation — smooth keyboard avoid -----------------------

fun setupKeyboardAnimation(scrollView: View, targetView: View) {
    ViewCompat.setWindowInsetsAnimationCallback(
        scrollView,
        object : WindowInsetsAnimationCompat.Callback(DISPATCH_MODE_STOP) {

            override fun onProgress(
                insets: WindowInsetsCompat,
                runningAnimations: MutableList<WindowInsetsAnimationCompat>
            ): WindowInsetsCompat {
                val imeInsets = insets.getInsets(WindowInsetsCompat.Type.ime())
                val barsInsets = insets.getInsets(WindowInsetsCompat.Type.systemBars())
                scrollView.updatePadding(bottom = (imeInsets.bottom - barsInsets.bottom).coerceAtLeast(0))
                return insets
            }
        }
    )
}

// ---- Jetpack Compose --------------------------------------------------------

/*
// In your top-level Composable (e.g. MainActivity setContent block):

setContent {
    MyAppTheme {
        Scaffold(
            modifier = Modifier.fillMaxSize()
        ) { innerPadding ->
            // innerPadding already accounts for system bars
            AppNavHost(modifier = Modifier.padding(innerPadding))
        }
    }
}

// If Scaffold isn't used, apply insets manually:

Box(
    modifier = Modifier
        .fillMaxSize()
        .windowInsetsPadding(WindowInsets.systemBars)
) {
    // content
}
*/