from llama_cloud import AsyncLlamaCloud
from ..config import get_ocr_key
import asyncio, json
from pathlib import Path

data_schema = {
    "additionalProperties": False,
    "properties": {
        "merchant_name": {
        "description": "Store or merchant name",
        "type": "string"
        },
        "date": {
        "description": "Transaction date (YYYY-MM-DD)",
        "type": "string"
        },
        "items": {
        "description": "Purchased items",
        "items": {
            "properties": {
            "name": {
                "description": "Item name",
                "type": "string"
            },
            "quantity": {
                "description": "Quantity purchased",
                "type": "number"
            },
            "price": {
                "description": "Item price",
                "type": "number"
            }
            },
            "required": [
            "name",
            "quantity",
            "price"
            ],
            "type": "object"
        },
        "type": "array"
        },
        "subtotal": {
        "anyOf": [
            {
            "description": "Subtotal before tax",
            "type": "number"
            },
            {
            "type": "null"
            }
        ],
        "description": "Subtotal before tax"
        },
        "tax": {
        "anyOf": [
            {
            "description": "Tax amount",
            "type": "number"
            },
            {
            "type": "null"
            }
        ],
        "description": "Tax amount"
        },
        "total": {
        "description": "Total amount paid",
        "type": "number"
        },
        "payment_method": {
        "anyOf": [
            {
            "description": "How the purchase was paid",
            "type": "string"
            },
            {
            "type": "null"
            }
        ],
        "description": "How the purchase was paid"
        }
    },
    "required": [
        "merchant_name",
        "date",
        "items",
        "subtotal",
        "tax",
        "total",
        "payment_method"
    ],
    "type": "object"
    }


async def get_receipt_info():
    api_key = get_ocr_key()

    client = AsyncLlamaCloud(api_key=api_key)

    file_obj = await client.files.create(file="./fast_app/api/receipt.jpg", purpose="parse")

    job = await client.extract.create(
        file_input=file_obj.id,
        configuration={
            "data_schema": data_schema,
            "tier": "agentic",
            "extraction_target": "per_doc",
            "parse_tier": "agentic",
            "cite_sources": True,
            "confidence_scores": True
        },
    )

    while job.status not in("COMPLETED", "FAILED", "CANCELLED"):
        await asyncio.sleep(2)
        job = await client.extract.get(job.id)

    if job.status != "COMPLETED":
        raise RuntimeError(f"Extract job {job.id} ended in {job.status}:{job.error_message}")

        # Persist extracted JSON to disk
    Path("extracted.json").write_text(json.dumps(job.extract_result, indent=2))
    print(json.dumps(job.extract_result, indent=2))

    # Per-field citation / confidence metadata
    if job.extract_metadata and job.extract_metadata.field_metadata:
        for field, meta in (job.extract_metadata.field_metadata.document_metadata or {}).items():
            print(f"{field}: {meta}")

    return "My god it worked!"

def check_json():
    return json.dumps(data_schema)

if __name__ == "__main__":
    asyncio.run(get_receipt_info())
