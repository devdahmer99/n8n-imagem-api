const axios = require('axios');

async function testAPI() {
  const API_URL = 'http://localhost:3001';
  const TEST_IMAGE = 'https://arquivos.mercos.com/media/imagem_produto/311785/603aa4c8-99e1-11ee-8253-72efcca7e9b3.jpg';

  console.log('🧪 Testando API...\n');

  try {
    // Teste 1: POST
    console.log('📤 Teste POST:');
    const postResponse = await axios.post(`${API_URL}/convert-image`, {
      imageUrl: TEST_IMAGE
    });
    
    console.log('✅ Status:', postResponse.status);
    console.log('📊 Tipo MIME:', postResponse.data.data.mimeType);
    console.log('📏 Tamanho base64:', postResponse.data.data.base64Image.length);
    console.log('');

    // Teste 2: GET
    console.log('📥 Teste GET:');
    const getResponse = await axios.get(`${API_URL}/convert-image?url=${encodeURIComponent(TEST_IMAGE)}`);
    
    console.log('✅ Status:', getResponse.status);
    console.log('📊 Tipo MIME:', getResponse.data.data.mimeType);
    console.log('');

    // Teste 3: Health check
    console.log('❤️  Health check:');
    const healthResponse = await axios.get(`${API_URL}/health`);
    console.log('✅ Status:', healthResponse.data.status);
    console.log('⏰ Uptime:', healthResponse.data.uptime, 'segundos');

    console.log('\n🎉 Todos os testes passaram!');

  } catch (error) {
    console.error('❌ Erro no teste:', error.message);
    if (error.response) {
      console.error('📄 Resposta:', error.response.data);
    }
  }
}

testAPI();