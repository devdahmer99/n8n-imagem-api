const express = require('express');
const axios = require('axios');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const crypto = require('crypto');
const multer = require('multer');

const storage = multer.memoryStorage();
const upload = multer({ storage: storage });
const app = express();
const PORT = process.env.PORT || 3001;

app.use(helmet());
app.use(cors());
app.use(morgan('combined'));
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

function decryptWhatsappMedia(mediaKeyBase64, encryptedFileBuffer) {
  // Decodifica a chave de mídia
  const mediaKey = Buffer.from(mediaKeyBase64, 'base64');

  // Pega o IV (os primeiros 16 bytes)
  const iv = encryptedFileBuffer.slice(0, 16);
  
  // Pega o restante do arquivo para ser o ciphertext
  // Não vamos mais cortar o final, vamos deixar a biblioteca lidar com isso.
  const ciphertext = encryptedFileBuffer.slice(16);

  // Cria o decipher. Por padrão, ele já usa o padding correto (PKCS#7).
  const decipher = crypto.createDecipheriv('aes-256-cbc', mediaKey, iv);

  // Descriptografa. A função .final() vai remover o padding extra automaticamente.
  const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);

  return decrypted;
}



async function imageUrlToBase64(imageUrl) {
  try {
    const response = await axios({
      method: 'GET',
      url: imageUrl,
      responseType: 'arraybuffer',
      timeout: 30000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; n8n-image-api/1.0)',
        'Accept': 'image/*'
      },
      maxContentLength: 50 * 1024 * 1024,
      maxBodyLength: 50 * 1024 * 1024
    });

    const base64String = Buffer.from(response.data).toString('base64');
    
    const contentType = response.headers['content-type'] || 'image/jpeg';
    
    return {
      success: true,
      data: {
        base64Image: base64String,
        mimeType: contentType,
        dataUri: `data:${contentType};base64,${base64String}`,
        originalUrl: imageUrl,
        size: response.data.length,
        vertexAI: {
          inlineData: {
            mimeType: contentType,
            data: base64String
          }
        }
      }
    };

  } catch (error) {
    console.error('Erro ao processar imagem:', error.message);
    
    return {
      success: false,
      error: {
        message: error.message,
        code: error.code || 'UNKNOWN_ERROR',
        status: error.response ? error.response.status : null
      }
    };
  }
}

app.post('/decrypt-whatsapp-image', upload.single('encryptedFile'), async (req, res) => {
  try {
    const { mediaKey } = req.body;
    const encryptedFile = req.file;

    // Validação
    if (!encryptedFile) {
      return res.status(400).json({ success: false, error: { message: 'Arquivo .enc (encryptedFile) é obrigatório.', code: 'MISSING_FILE' } });
    }
    if (!mediaKey) {
      return res.status(400).json({ success: false, error: { message: 'Chave de mídia (mediaKey) é obrigatória.', code: 'MISSING_KEY' } });
    }

    // Chama a função de descriptografia
    const decryptedImageBuffer = decryptWhatsappMedia(mediaKey, encryptedFile.buffer);

    // Retorna a imagem diretamente!
    // Assumimos que é JPEG, mas o ideal seria detectar o tipo. Para o WhatsApp, é um bom padrão.
    res.setHeader('Content-Type', 'image/jpeg');
    res.send(decryptedImageBuffer);

  } catch (error) {
    console.error('Erro ao descriptografar imagem:', error);
    res.status(500).json({
      success: false,
      error: {
        message: 'Falha ao descriptografar o arquivo. Verifique a chave e o arquivo.',
        code: 'DECRYPTION_FAILED'
      }
    });
  }
});

app.post('/convert-image', async (req, res) => {
  try {
    const { imageUrl, url } = req.body;
    const targetUrl = imageUrl || url;

    if (!targetUrl) {
      return res.status(400).json({
        success: false,
        error: {
          message: 'URL da imagem é obrigatória',
          code: 'MISSING_URL'
        }
      });
    }

    try {
      new URL(targetUrl);
    } catch {
      return res.status(400).json({
        success: false,
        error: {
          message: 'URL inválida',
          code: 'INVALID_URL'
        }
      });
    }

    const result = await imageUrlToBase64(targetUrl);
    
    if (result.success) {
      res.status(200).json(result);
    } else {
      res.status(400).json(result);
    }

  } catch (error) {
    console.error('Erro interno:', error);
    res.status(500).json({
      success: false,
      error: {
        message: 'Erro interno do servidor',
        code: 'INTERNAL_ERROR'
      }
    });
  }
});

app.get('/convert-image', async (req, res) => {
  const { url } = req.query;
  
  if (!url) {
    return res.status(400).json({
      success: false,
      error: {
        message: 'Parâmetro ?url= é obrigatório',
        code: 'MISSING_URL'
      }
    });
  }

  const result = await imageUrlToBase64(url);
  
  if (result.success) {
    res.status(200).json(result);
  } else {
    res.status(400).json(result);
  }
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

app.get('/', (req, res) => {
  res.json({
    name: 'n8n Image to Base64 API',
    version: '1.0.0',
    endpoints: {
      'POST /convert-image': 'Converte URL da imagem para base64',
      'GET /convert-image?url=': 'Converte URL da imagem via GET',
      'GET /health': 'Health check',
      'POST /decrypt-whatsapp-image': 'Recebe um arquivo .enc e a media_key para retornar a imagem descriptografada.'
    },
    usage: {
      post: 'POST /convert-image { "imageUrl": "https://exemplo.com/imagem.jpg" }',
      get: 'GET /convert-image?url=https://exemplo.com/imagem.jpg'
    }
  });
});

app.use((err, req, res, next) => {
  console.error('Erro não tratado:', err);
  res.status(500).json({
    success: false,
    error: {
      message: 'Erro interno do servidor',
      code: 'INTERNAL_ERROR'
    }
  });
});

app.use('*', (req, res) => {
  res.status(404).json({
    success: false,
    error: {
      message: 'Endpoint não encontrado',
      code: 'NOT_FOUND'
    }
  });
});

app.listen(PORT, () => {
  console.log(`🚀 API rodando na porta ${PORT}`);
  console.log(`📝 Documentação: http://localhost:${PORT}`);
  console.log(`❤️  Health check: http://localhost:${PORT}/health`);
});

module.exports = app;
