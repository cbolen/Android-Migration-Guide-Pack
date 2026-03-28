/**
 * Storage patterns for Android 11–15.
 *
 * No MANAGE_EXTERNAL_STORAGE needed for these patterns.
 * Use getExternalFilesDir() for app files, MediaStore for shared media,
 * SAF for user-selected files.
 */

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import java.io.InputStream
import java.io.OutputStream

// ---- App-specific external files (no permission needed) ---------------------

fun writeAppFile(context: Context, filename: String, content: String) {
    val file = java.io.File(context.getExternalFilesDir(null), filename)
    file.writeText(content)
}

fun readAppFile(context: Context, filename: String): String? {
    val file = java.io.File(context.getExternalFilesDir(null), filename)
    return if (file.exists()) file.readText() else null
}

// ---- MediaStore — export file to Downloads ----------------------------------

fun exportToDownloads(context: Context, filename: String, mimeType: String, write: (OutputStream) -> Unit): Uri? {
    val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, filename)
        put(MediaStore.Downloads.MIME_TYPE, mimeType)
        put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
    }
    val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
    uri?.let { context.contentResolver.openOutputStream(it)?.use(write) }
    return uri
}

// Example: export a CSV
fun exportCsv(context: Context, csvContent: String) {
    exportToDownloads(context, "export.csv", "text/csv") { stream ->
        stream.write(csvContent.toByteArray())
    }
}

// ---- MediaStore — save image to Pictures ------------------------------------

fun saveImageToPictures(context: Context, filename: String, write: (OutputStream) -> Unit): Uri? {
    val values = ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, filename)
        put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
        put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES)
    }
    val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
    uri?.let { context.contentResolver.openOutputStream(it)?.use(write) }
    return uri
}

// ---- SAF — user picks a file ------------------------------------------------

class StorageActivity : AppCompatActivity() {

    private val pickFile = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri?.let { readFromUri(it) }
    }

    private val createFile = registerForActivityResult(
        ActivityResultContracts.CreateDocument("application/octet-stream")
    ) { uri ->
        uri?.let { writeToUri(it) }
    }

    fun openFilePicker(mimeTypes: Array<String> = arrayOf("*/*")) {
        pickFile.launch(mimeTypes)
    }

    fun openFileSaver(suggestedName: String) {
        createFile.launch(suggestedName)
    }

    private fun readFromUri(uri: Uri) {
        contentResolver.openInputStream(uri)?.use { stream: InputStream ->
            val bytes = stream.readBytes()
            // process bytes
        }
    }

    private fun writeToUri(uri: Uri) {
        contentResolver.openOutputStream(uri)?.use { stream: OutputStream ->
            stream.write("content".toByteArray())
        }
    }
}

// ---- FileProvider — share app-specific file with another app ----------------

import androidx.core.content.FileProvider
import android.content.Intent
import java.io.File

fun shareFile(context: Context, file: File, mimeType: String) {
    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file
    )
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = mimeType
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Share"))
}