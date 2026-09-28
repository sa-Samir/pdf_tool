package com.samir.pdf_toolbox

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Copies finished documents out to wherever the user picks (requirements.md 6).
 *
 * Uses the Storage Access Framework, so the app needs no storage permission at
 * all and never asks for MANAGE_EXTERNAL_STORAGE. The user's choice of
 * destination *is* the grant.
 *
 * Streams through an 8 KB buffer rather than taking bytes across the channel:
 * requirements.md 13 allows inputs up to 200 MB and caps peak RSS at 400 MB.
 *
 * Always a copy. The app's own file is never touched, let alone removed.
 */
class MainActivity : FlutterActivity() {

    private var pending: MethodChannel.Result? = null
    private var pendingPaths: List<String> = emptyList()
    private var pendingScan: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::onMethodCall)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRINT_CHANNEL)
            .setMethodCallHandler(::onPrintCall)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCAN_CHANNEL)
            .setMethodCallHandler(::onScanCall)
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "save") {
            result.notImplemented()
            return
        }
        val paths = call.argument<List<String>>("paths").orEmpty()
        if (paths.isEmpty()) {
            result.success(reply("cancelled", 0))
            return
        }
        if (pending != null) {
            result.error("busy", "A save is already in progress.", null)
            return
        }

        pending = result
        pendingPaths = paths
        try {
            if (paths.size == 1) {
                val name = File(paths.first()).name
                // One file: let the user name it and place it exactly.
                startActivityForResult(
                    Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mimeFor(name)
                        putExtra(Intent.EXTRA_TITLE, name)
                    },
                    REQUEST_CREATE,
                )
            } else {
                // Several: one folder choice beats one dialog per file.
                startActivityForResult(
                    Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        // Opened at Documents on purpose. Since Android 11 a
                        // tree grant is refused for the Download folder, the
                        // internal-storage root and Android/data, and the
                        // picker remembers wherever it was last used -- so
                        // without this it routinely opens on a folder whose
                        // "Use this folder" button is greyed out, which reads
                        // as the feature being broken.
                        putExtra(DocumentsContract.EXTRA_INITIAL_URI, DOCUMENTS)
                    },
                    REQUEST_TREE,
                )
            }
        } catch (e: Exception) {
            settle(reply("failed", 0))
        }
    }

    /**
     * Hands a PDF to the system print UI (requirements.md 6).
     *
     * The file is streamed into the descriptor the print framework supplies,
     * so a large document is never held in memory. Reports only that the
     * system took it: what the user then does in that UI -- print, save as
     * PDF, or back out -- is theirs, and this app does not claim to know.
     */
    private fun onPrintCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "print") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.success(mapOf("status" to "failed"))
            return
        }
        val source = File(path)
        if (!source.exists()) {
            result.success(mapOf("status" to "failed"))
            return
        }

        val manager = getSystemService(Context.PRINT_SERVICE) as? PrintManager
        if (manager == null) {
            result.success(mapOf("status" to "unsupported"))
            return
        }

        val jobName = call.argument<String>("jobName") ?: source.name
        val pageCount = call.argument<Int>("pageCount") ?: 0
        try {
            manager.print(jobName, PdfFileAdapter(source, pageCount), null)
            result.success(mapOf("status" to "started"))
        } catch (e: Exception) {
            result.success(mapOf("status" to "failed"))
        }
    }

    /**
     * Document scanning through ML Kit (requirements.md 3.10).
     *
     * The scanner is delivered by Google Play services and its module is
     * downloaded on first use, so availability is a real question with a real
     * answer -- asked before the tool is offered, never at capture time.
     */
    private fun onScanCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(playServicesReady())
            "scan" -> startScan(call.argument<Int>("pageLimit"), result)
            else -> result.notImplemented()
        }
    }

    private fun playServicesReady(): Boolean =
        GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(this) == ConnectionResult.SUCCESS

    private fun startScan(pageLimit: Int?, result: MethodChannel.Result) {
        if (!playServicesReady()) {
            result.success(scanReply("unavailable"))
            return
        }
        if (pendingScan != null) {
            result.error("busy", "A scan is already in progress.", null)
            return
        }
        pendingScan = result

        val options = GmsDocumentScannerOptions.Builder()
            // Importing from the gallery here would duplicate Images to PDF
            // and skip its page-layout options, so the camera only.
            .setGalleryImportAllowed(false)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            // FULL gives edge detection, perspective correction and the
            // enhancement filters requirements.md 3.10 asks for.
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .also { builder -> pageLimit?.let(builder::setPageLimit) }
            .build()

        GmsDocumentScanning.getClient(options)
            .getStartScanIntent(this)
            .addOnSuccessListener { sender ->
                try {
                    startIntentSenderForResult(sender, REQUEST_SCAN, null, 0, 0, 0)
                } catch (e: Exception) {
                    settleScan("failed")
                }
            }
            // Typically the Play services module failing to download, which is
            // the documented offline exception (requirements.md 7).
            .addOnFailureListener { settleScan("failed") }
    }

    /**
     * Copies the scanner's pages somewhere this app owns.
     *
     * The directory is wiped at the start of every capture: a scan is read
     * once, normalised into an operation's workspace, and never needed again,
     * so keeping it would only accumulate.
     */
    private fun copyPages(uris: List<Uri>): List<Map<String, Any?>> {
        val dir = File(cacheDir, "scans")
        if (dir.exists()) dir.deleteRecursively()
        dir.mkdirs()

        val pages = mutableListOf<Map<String, Any?>>()
        uris.forEachIndexed { index, uri ->
            val target = File(dir, "page-%03d.jpg".format(index + 1))
            val copied = contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { out -> input.copyTo(out) }
                true
            } ?: false
            if (copied) {
                pages.add(
                    mapOf(
                        "path" to target.absolutePath,
                        // Reported here so the review screen never has to stat
                        // the file from Dart.
                        "bytes" to target.length(),
                    )
                )
            }
        }
        return pages
    }

    private fun scanReply(
        status: String,
        pages: List<Map<String, Any?>> = emptyList(),
    ) = mapOf("status" to status, "pages" to pages)

    private fun settleScan(
        status: String,
        pages: List<Map<String, Any?>> = emptyList(),
    ) {
        pendingScan?.success(scanReply(status, pages))
        pendingScan = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_SCAN) {
            if (resultCode != Activity.RESULT_OK) {
                // Backing out of the camera is a choice, not a failure.
                settleScan("cancelled")
                return
            }
            val uris = GmsDocumentScanningResult
                .fromActivityResultIntent(data)
                ?.pages
                ?.map { it.imageUri }
                .orEmpty()
            if (uris.isEmpty()) {
                settleScan("cancelled")
                return
            }
            // Off the main thread: copying several full-page JPEGs would
            // otherwise stutter the return to the app.
            Thread {
                val pages = try {
                    copyPages(uris)
                } catch (e: Exception) {
                    emptyList()
                }
                runOnUiThread {
                    settleScan(if (pages.isEmpty()) "failed" else "captured", pages)
                }
            }.start()
            return
        }

        if (requestCode != REQUEST_CREATE && requestCode != REQUEST_TREE) return

        val destination = data?.data
        if (resultCode != Activity.RESULT_OK || destination == null) {
            // Backing out of the picker is a choice, not a failure.
            settle(reply("cancelled", 0))
            return
        }

        val paths = pendingPaths
        val intoTree = requestCode == REQUEST_TREE
        // Off the UI thread: a 200 MB document would otherwise freeze the app
        // mid-save (requirements.md 13).
        Thread {
            val saved = try {
                if (intoTree) copyIntoTree(destination, paths)
                else copyInto(destination, File(paths.first()))
            } catch (e: Exception) {
                0
            }
            val outcome = reply(
                if (saved > 0) "saved" else "failed",
                saved,
                describe(destination, intoTree),
            )
            runOnUiThread { settle(outcome) }
        }.start()
    }

    /** Streams one file onto an already-created document URI. */
    private fun copyInto(destination: Uri, source: File): Int {
        contentResolver.openOutputStream(destination)?.use { out ->
            source.inputStream().use { input -> input.copyTo(out) }
        } ?: return 0
        return 1
    }

    /**
     * Creates one document per file inside a chosen folder.
     *
     * Counts what actually landed rather than assuming: a partial result is
     * reported as a partial result.
     */
    private fun copyIntoTree(tree: Uri, paths: List<String>): Int {
        val parent = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        var saved = 0
        for (path in paths) {
            val source = File(path)
            try {
                val created = DocumentsContract.createDocument(
                    contentResolver,
                    parent,
                    mimeFor(source.name),
                    source.name,
                ) ?: continue
                saved += copyInto(created, source)
            } catch (e: Exception) {
                // Keep going: one unwritable name should not lose the rest.
            }
        }
        return saved
    }

    /** A destination worth showing, or null rather than something invented. */
    private fun describe(destination: Uri, intoTree: Boolean): String? = try {
        val id = if (intoTree) DocumentsContract.getTreeDocumentId(destination)
        else DocumentsContract.getDocumentId(destination)
        id.substringAfterLast(':').ifBlank { null }
    } catch (e: Exception) {
        null
    }

    private fun mimeFor(name: String): String {
        val extension = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
    }

    private fun reply(status: String, count: Int, location: String? = null) =
        mapOf("status" to status, "count" to count, "location" to location)

    private fun settle(outcome: Map<String, Any?>) {
        pending?.success(outcome)
        pending = null
        pendingPaths = emptyList()
    }

    /**
     * Feeds an existing PDF to the print framework without re-rendering it.
     *
     * Always writes the whole document and reports ALL_PAGES, which is the
     * truth: page-range selection is then the spooler's job, not ours. We do
     * not re-encode, so the printed file is the file.
     */
    private class PdfFileAdapter(
        private val source: File,
        private val pageCount: Int,
    ) : PrintDocumentAdapter() {

        private val main = Handler(Looper.getMainLooper())

        override fun onLayout(
            oldAttributes: PrintAttributes?,
            newAttributes: PrintAttributes?,
            cancellationSignal: CancellationSignal?,
            callback: LayoutResultCallback,
            extras: Bundle?,
        ) {
            if (cancellationSignal?.isCanceled == true) {
                callback.onLayoutCancelled()
                return
            }
            val info = PrintDocumentInfo.Builder(source.name)
                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                .setPageCount(
                    if (pageCount > 0) pageCount
                    else PrintDocumentInfo.PAGE_COUNT_UNKNOWN
                )
                .build()
            callback.onLayoutFinished(info, true)
        }

        override fun onWrite(
            pages: Array<out PageRange>?,
            destination: ParcelFileDescriptor,
            cancellationSignal: CancellationSignal?,
            callback: WriteResultCallback,
        ) {
            // Off the main thread: the print framework calls this on it, and a
            // 200 MB document would otherwise freeze the UI (requirements.md 13).
            Thread {
                val error = try {
                    source.inputStream().use { input ->
                        FileOutputStream(destination.fileDescriptor).use { out ->
                            input.copyTo(out)
                        }
                    }
                    null
                } catch (e: Exception) {
                    e.message ?: "could not write the document"
                }
                main.post {
                    if (cancellationSignal?.isCanceled == true) {
                        callback.onWriteCancelled()
                    } else if (error == null) {
                        callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                    } else {
                        callback.onWriteFailed(error)
                    }
                }
            }.start()
        }
    }

    private companion object {
        const val CHANNEL = "com.samir.pdf_toolbox/device_export"
        const val PRINT_CHANNEL = "com.samir.pdf_toolbox/print"
        const val SCAN_CHANNEL = "com.samir.pdf_toolbox/scan"
        const val REQUEST_CREATE = 0x5AF1
        const val REQUEST_TREE = 0x5AF2
        const val REQUEST_SCAN = 0x5AF3

        /** Somewhere a tree grant is actually allowed to land. */
        val DOCUMENTS: Uri = DocumentsContract.buildDocumentUri(
            "com.android.externalstorage.documents",
            "primary:Documents",
        )
    }
}
