package com.samir.pdf_toolbox

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::onMethodCall)
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
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

    private companion object {
        const val CHANNEL = "com.samir.pdf_toolbox/device_export"
        const val REQUEST_CREATE = 0x5AF1
        const val REQUEST_TREE = 0x5AF2

        /** Somewhere a tree grant is actually allowed to land. */
        val DOCUMENTS: Uri = DocumentsContract.buildDocumentUri(
            "com.android.externalstorage.documents",
            "primary:Documents",
        )
    }
}
