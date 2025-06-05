const express = require('express');
const axios = require('axios');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const app = express();
const PORT = process.env.PORT || 3001;

// Middlewares
app.use(helmet());
app.use(cors());
app.use(morgan('combined'));
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Função para converter URL da imagem para base64
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
      maxContentLength: 50 * 1024 * 1024, // 50MB max
      maxBodyLength: 50 * 1024 * 1024
    });

    // Converte para base64
    const base64String = Buffer.from(response.data).toString('base64');
    
    // Detecta o tipo MIME
    const contentType = response.headers['content-type'] || 'image/jpeg';
    
    return {
      success: true,
      data: {
        base64Image: base64String,
        mimeType: contentType,
        dataUri: `data:${contentType};base64,${base64String}`,
        originalUrl: imageUrl,
        size: response.data.length,
        // Formato específico para Vertex AI
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

// Endpoint principal para converter imagem
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

    // Valida se é uma URL válida
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

// Endpoint GET para teste rápido
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

// Health check
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Endpoint de informações
app.get('/', (req, res) => {
  res.json({
    name: 'n8n Image to Base64 API',
    version: '1.0.0',
    endpoints: {
      'POST /convert-image': 'Converte URL da imagem para base64',
      'GET /convert-image?url=': 'Converte URL da imagem via GET',
      'GET /health': 'Health check'
    },
    usage: {
      post: 'POST /convert-image { "imageUrl": "https://exemplo.com/imagem.jpg" }',
      get: 'GET /convert-image?url=https://exemplo.com/imagem.jpg'
    }
  });
});

// Middleware de erro global
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

// Middleware para rotas não encontradas
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